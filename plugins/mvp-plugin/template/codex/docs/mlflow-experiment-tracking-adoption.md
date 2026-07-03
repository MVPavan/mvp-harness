# Adoption Runbook — MLflow Experiment Tracking

**Purpose.** Hand this file to an agent in **any** Python project and it can reproduce the exact
experiment-tracking setup: a dockerised MLflow server (Postgres-backed) + a generic, reusable `track()`
toolkit + a skill/policy so agents use it consistently. Nothing here is project-specific except the
**placeholders** below — fill those in and follow the steps top to bottom.

## 0. Placeholders (substitute throughout)

| Placeholder | Meaning | Example |
|---|---|---|
| `{{PKG}}` | your Python package name (under `src/`) | `myapp` |
| `{{PG_CONTAINER}}` | existing Postgres **container name** to reuse | `myapp-postgres` |
| `{{PG_USER}}` / `{{PG_PASSWORD}}` | Postgres creds | `myapp` / `myapp_dev` |
| `{{NETWORK}}` | the docker network the Postgres container is on | `dev-stack_default` |
| `{{INFRA_DIR}}` | where your compose stacks live | `infra` |

> **No existing Postgres?** Either add a `postgres:16-alpine` service to this compose (give it a volume +
> healthcheck) and point the backend at it, or use SQLite for dev only
> (`--backend-store-uri sqlite:///mlflow.db`) — but Postgres is required for concurrent/parallel runs.

## 1. What you are reproducing & the scope fence

- **MLflow = component-experiment system of record.** It records every experiment's params, metrics,
  output files (artifacts), and (for LLM work) traces, with one UI to compare runs.
- **Scope fence — MLflow must NOT own:** production LLM tracing (if the project has Langfuse/Phoenix/etc.,
  that stays the trace SoR), operational logs/metrics (Grafana/Loki/OTel), an end-to-end eval framework
  (if one exists, e.g. Pydantic Evals), or anything on a request/production hot path. MLflow is a
  batch/experiment tool only.
- **Key properties of the toolkit:** lazy-imports mlflow, **degrades to a no-op if mlflow/server is absent
  (never blocks an experiment)**, auto-captures provenance (git + lockfile), uses **flat metric names**,
  and has a parallel-safe path for concurrent runs.

## 2. Part A — the dockerised MLflow stack

Create a **standalone** stack folder `{{INFRA_DIR}}/mlflow-stack/` (kept separate from the core runtime —
it's optional tooling). The server reuses the existing Postgres (a new `mlflow` database via a one-shot
sidecar) and joins the existing docker network.

### `{{INFRA_DIR}}/mlflow-stack/mlflow.Dockerfile`

```dockerfile
# MLflow tracking server + the Postgres driver (psycopg2 is absent from the base image).
FROM ghcr.io/mlflow/mlflow:v3.13.0
RUN pip install --no-cache-dir psycopg2-binary
```

### `{{INFRA_DIR}}/mlflow-stack/docker-compose.yml`

```yaml
# MLflow experiment-tracking stack — separate from the core stack.
# Reuses the existing Postgres (new `mlflow` DB via mlflow-db-init); joins its network (external).
# Bring the Postgres-owning stack up first. Then:
#   docker compose -f {{INFRA_DIR}}/mlflow-stack/docker-compose.yml up -d --build
name: mlflow-stack

services:
  mlflow-db-init:                      # one-shot: create the `mlflow` database (idempotent)
    image: postgres:16-alpine
    container_name: mlflow-db-init
    networks: [backend]
    environment:
      PGPASSWORD: ${PG_PASSWORD:-{{PG_PASSWORD}}}
      PGUSER: ${PG_USER:-{{PG_USER}}}
    entrypoint: ["sh", "-c"]
    command:
      - |
        set -e
        until pg_isready -h {{PG_CONTAINER}} -U "$$PGUSER" -q; do echo "waiting for postgres..."; sleep 1; done
        psql -h {{PG_CONTAINER}} -d postgres -tAc "SELECT 1 FROM pg_database WHERE datname='mlflow'" | grep -q 1 \
          || psql -h {{PG_CONTAINER}} -d postgres -c "CREATE DATABASE mlflow OWNER \"$$PGUSER\""
    restart: "no"

  mlflow:
    build:
      context: .
      dockerfile: mlflow.Dockerfile
    container_name: mlflow
    networks: [backend]
    depends_on:
      mlflow-db-init:
        condition: service_completed_successfully
    ports:
      - "127.0.0.1:5000:5000"           # localhost-only (OSS MLflow has no auth; traces can carry PII)
    user: "${MLFLOW_UID:-1000}:${MLFLOW_GID:-1000}"   # write artifacts as the host user (export MLFLOW_UID/GID)
    volumes:
      # Bind-mount artifacts to a repo-local, browsable, gitignored folder. The path is relative to THIS
      # compose file's dir — `../../.mlflow-artifacts` assumes it sits at {{INFRA_DIR}}/mlflow-stack/ (two
      # levels under the repo root). For a SEPARATE disk, use an absolute path on that disk instead.
      - ../../.mlflow-artifacts:/mlartifacts
    command: >
      mlflow server
      --backend-store-uri postgresql+psycopg2://${PG_USER:-{{PG_USER}}}:${PG_PASSWORD:-{{PG_PASSWORD}}}@{{PG_CONTAINER}}:5432/mlflow
      --artifacts-destination /mlartifacts
      --serve-artifacts
      --host 0.0.0.0 --port 5000
    restart: unless-stopped
    healthcheck:
      test: ["CMD-SHELL", "python -c 'import urllib.request; urllib.request.urlopen(\"http://localhost:5000/health\", timeout=2)' || exit 1"]
      interval: 10s
      timeout: 5s
      retries: 5
      start_period: 20s

networks:
  backend:
    name: {{NETWORK}}                   # the existing network that provides {{PG_CONTAINER}}
    external: true
```

> Before the first `up`, create the bind-mount target so it exists + is gitignored, and export your uid:
> ```bash
> mkdir -p .mlflow-artifacts
> printf '# MLflow artifact store — bind-mounted by {{INFRA_DIR}}/mlflow-stack/. Large/binary; never commit.\n*\n!.gitignore\n' > .mlflow-artifacts/.gitignore
> export MLFLOW_UID=$(id -u) MLFLOW_GID=$(id -g)
> ```

**Bring it up + verify:**

```bash
docker compose -f {{INFRA_DIR}}/mlflow-stack/docker-compose.yml up -d --build
docker logs mlflow-db-init           # expect: CREATE DATABASE (or already exists)
curl -s http://127.0.0.1:5000/health # expect: OK
```

### Why this design (don't skip)

- The official `ghcr.io/mlflow/mlflow` image **has no DB** (stateless) and **no Postgres driver** — hence
  the 2-line custom image and reusing the project's Postgres via a new `mlflow` logical database.
- `--serve-artifacts` makes the server proxy artifact read/write into the artifact dir, so the UI browses
  artifacts correctly and clients never need filesystem access.
- Artifacts **bind-mount** to a repo-local `.mlflow-artifacts/` (gitignored) so they are browsable /
  backupable instead of buried in a Docker volume, and `user:` runs the container as your host UID so the
  files are **host-owned**, not root-owned. *(Prefer a Docker named volume? Replace the bind with
  `mlflow-artifacts:/mlartifacts`, add a top-level `volumes: {mlflow-artifacts:}`, and drop `user:` —
  simpler, but the files then live in `/var/lib/docker/volumes/`, root-owned.)*
- Separate stack = independent lifecycle; the core stack can `down` without touching it.

### Where experiment output is stored

Two halves, in two places:

| Output | Stored in | Location |
|---|---|---|
| **Run metadata** — params, metrics, tags, run records, **traces** | the `mlflow` **database** in the reused Postgres | inside the Postgres container's data volume |
| **Artifacts** — the output *files* (`summary.json`, tables, reports, trace data) | the **repo-local `.mlflow-artifacts/`** (bind-mounted to `/mlartifacts`, served via the proxy) | `./.mlflow-artifacts/<exp_id>/<run_id>/artifacts/…` — browsable, **host-owned**, **gitignored** |
| **Large in-place datasets** via `run.log_reference(...)` | **not copied** — only a path + content-hash tag is stored | the file stays where it already is (e.g. `experiments/`, `eval-results/`) |

Notes & caveats:

- **Metadata stays in Postgres** — you cannot put *everything* in `.mlflow-artifacts/` without dropping
  Postgres for a SQLite file (don't — you'd lose concurrency-safety for parallel runs).
- **Disk:** the bind-mount lives wherever the repo lives. If the repo and Docker's `/var/lib/docker` are
  on the **same disk**, bind-mounting does **not** change which disk fills — point the bind at a path on
  another disk if you need true separation.
- **Size:** bind-mounting makes growth *visible*, not smaller. Reclaim with `mlflow gc` (after deleting
  old runs), `run.log_reference()` for big files, trimming what you log, or S3
  (`--artifacts-destination s3://<bucket>` + `boto3` in the image).
- A run's *local* working files (whatever your script writes to disk) are separate; the toolkit uploads
  only what you pass to `log_*`.

## 3. Part B — the `track()` toolkit (the reusable library)

Create the package `src/{{PKG}}/infrastructure/tracking/` with the six files below **verbatim** (replace
`{{PKG}}` with your package name). It mirrors a vendor-neutral adapter pattern (Protocol + real backend +
Null backend + factory) and lazy-imports mlflow so the package imports fine even when mlflow is absent.

> Layout assumption: files live at `src/{{PKG}}/infrastructure/tracking/`. `provenance.py` infers the repo
> root via `Path(__file__).resolve().parents[4]` (= `src/{{PKG}}/infrastructure/tracking/` → repo root).
> If your layout differs, adjust that index.

### `src/{{PKG}}/infrastructure/tracking/constants.py`

```python
"""Constants for the experiment-tracking toolkit.

All tag keys, param keys, default tracking URI, autolog flavors, and run-status
values are declared here once (no loose string literals).
"""

from __future__ import annotations

from enum import StrEnum
from typing import Final

DEFAULT_TRACKING_URI: Final[str] = "http://127.0.0.1:5000"
ENV_TRACKING_URI: Final[str] = "MLFLOW_TRACKING_URI"

# Only flavors whose SDK is importable actually fire; the rest are recorded as skipped.
DEFAULT_AUTOLOG_FLAVORS: Final[tuple[str, ...]] = ("pydantic_ai", "openai", "litellm")
AUTOLOG_STATUS_ENABLED: Final[str] = "enabled"
AUTOLOG_STATUS_SKIPPED_PREFIX: Final[str] = "skipped:"


class TagKey(StrEnum):
    """Standard MLflow tag keys used as the comparison axis."""

    STUDY = "study"
    VARIANT = "variant"
    MODEL = "model"
    PROMPT = "prompt"
    DATASET = "dataset"
    SWEEP_ID = "sweep_id"
    RUN_LEVEL = "run_level"


RUN_LEVEL_VARIANT: Final[str] = "variant"


class ProvenanceParam(StrEnum):
    """Param keys for reproducibility provenance."""

    GIT_SHA = "git_sha"
    GIT_DIRTY = "git_dirty"
    GIT_DIFF_HASH = "git_diff_hash"
    UV_LOCK_HASH = "uv_lock_hash"


TRACING_PARAM_PREFIX: Final[str] = "tracing."
CONFIG_SNAPSHOT_ARTIFACT: Final[str] = "config_snapshot.json"
PROMPT_ARTIFACT_PATH: Final[str] = "prompt"
PROMPT_ARTIFACT_FILE: Final[str] = "prompt.txt"

REFERENCE_TAG_PREFIX: Final[str] = "reference."
REFERENCE_HASH_TAG_PREFIX: Final[str] = "reference_sha256."
DEFAULT_REFERENCE_KEY: Final[str] = "data"


class RunStatus(StrEnum):
    """Terminal MLflow run statuses."""

    FINISHED = "FINISHED"
    FAILED = "FAILED"


PROVENANCE_UNKNOWN: Final[str] = "unknown"
UV_LOCK_FILENAME: Final[str] = "uv.lock"
HASH_CHUNK_BYTES: Final[int] = 65536
GIT_SUBPROCESS_TIMEOUT_SECONDS: Final[float] = 5.0
```

### `src/{{PKG}}/infrastructure/tracking/config.py`

```python
"""Configuration for the experiment-tracking toolkit (frozen Pydantic, injected)."""

from __future__ import annotations

import os

from pydantic import BaseModel, ConfigDict, Field

from {{PKG}}.infrastructure.tracking.constants import (
    DEFAULT_AUTOLOG_FLAVORS,
    DEFAULT_TRACKING_URI,
    ENV_TRACKING_URI,
)


class TrackingConfig(BaseModel):
    """Settings for experiment tracking. ``enabled=False`` selects the no-op path."""

    model_config = ConfigDict(frozen=True)

    enabled: bool = True
    tracking_uri: str = DEFAULT_TRACKING_URI
    default_tags: dict[str, str] = Field(default_factory=dict)
    autolog_flavors: tuple[str, ...] = DEFAULT_AUTOLOG_FLAVORS
    flush_on_exit: bool = True

    @classmethod
    def from_env(cls) -> TrackingConfig:
        """Build a config, reading ``MLFLOW_TRACKING_URI`` if set (the only env read)."""
        uri = os.environ.get(ENV_TRACKING_URI)
        if uri:
            return cls(tracking_uri=uri)
        return cls()
```

### `src/{{PKG}}/infrastructure/tracking/provenance.py`

```python
"""Reproducibility provenance (git SHA, dirty flag, diff hash, uv.lock hash). No MLflow dep."""

from __future__ import annotations

import hashlib
import subprocess
from pathlib import Path

import structlog
from pydantic import BaseModel, ConfigDict

from {{PKG}}.infrastructure.tracking.constants import (
    GIT_SUBPROCESS_TIMEOUT_SECONDS,
    HASH_CHUNK_BYTES,
    PROVENANCE_UNKNOWN,
    UV_LOCK_FILENAME,
    ProvenanceParam,
)

logger = structlog.get_logger(component="tracking.provenance")

_GIT_REV_PARSE: tuple[str, ...] = ("git", "rev-parse", "HEAD")
_GIT_STATUS_PORCELAIN: tuple[str, ...] = ("git", "status", "--porcelain")
_GIT_DIFF: tuple[str, ...] = ("git", "diff", "HEAD")


class Provenance(BaseModel):
    """Reproducibility snapshot for a single run."""

    model_config = ConfigDict(frozen=True)

    git_sha: str
    git_dirty: bool
    git_diff_hash: str | None = None
    uv_lock_hash: str | None = None
    config_snapshot: dict[str, object] | None = None
    prompt_text: str | None = None

    def to_params(self) -> dict[str, str]:
        """Render reproducibility scalars as flat string params (snapshot/prompt are artifacts)."""
        params: dict[str, str] = {
            ProvenanceParam.GIT_SHA.value: self.git_sha,
            ProvenanceParam.GIT_DIRTY.value: str(self.git_dirty),
        }
        if self.git_diff_hash is not None:
            params[ProvenanceParam.GIT_DIFF_HASH.value] = self.git_diff_hash
        if self.uv_lock_hash is not None:
            params[ProvenanceParam.UV_LOCK_HASH.value] = self.uv_lock_hash
        return params


def _repo_root() -> Path:
    """Repo root, four parents up from src/<pkg>/infrastructure/tracking/provenance.py."""
    return Path(__file__).resolve().parents[4]


def _run_git(args: tuple[str, ...], cwd: Path) -> str | None:
    """Run a git command, returning stripped stdout or ``None`` on any failure (never raises)."""
    try:
        out = subprocess.run(
            list(args),
            cwd=cwd,
            capture_output=True,
            text=True,
            timeout=GIT_SUBPROCESS_TIMEOUT_SECONDS,
            check=True,
        )
    except (OSError, subprocess.SubprocessError):
        return None
    return out.stdout.strip()


def _hash_bytes(data: bytes) -> str:
    """Hex SHA-256 of in-memory bytes."""
    return hashlib.sha256(data).hexdigest()


def _hash_file(path: Path) -> str | None:
    """Hex SHA-256 of a file in bounded chunks, or ``None`` if unreadable."""
    digest = hashlib.sha256()
    try:
        with path.open("rb") as handle:
            for chunk in iter(lambda: handle.read(HASH_CHUNK_BYTES), b""):
                digest.update(chunk)
    except OSError:
        return None
    return digest.hexdigest()


def gather_provenance(
    prompt_text: str | None = None,
    config_snapshot: dict[str, object] | None = None,
    repo_root: Path | None = None,
) -> Provenance:
    """Collect git + lock provenance; every field degrades independently, never raises."""
    root = repo_root if repo_root is not None else _repo_root()

    sha = _run_git(_GIT_REV_PARSE, root)
    status = _run_git(_GIT_STATUS_PORCELAIN, root)
    dirty = bool(status) if status is not None else False

    diff_hash: str | None = None
    if dirty:
        diff = _run_git(_GIT_DIFF, root)
        if diff:
            diff_hash = _hash_bytes(diff.encode("utf-8"))

    lock_hash = _hash_file(root / UV_LOCK_FILENAME)

    if sha is None:
        logger.warning("provenance_git_unavailable", repo_root=str(root))

    return Provenance(
        git_sha=sha if sha is not None else PROVENANCE_UNKNOWN,
        git_dirty=dirty,
        git_diff_hash=diff_hash,
        uv_lock_hash=lock_hash,
        config_snapshot=config_snapshot,
        prompt_text=prompt_text,
    )
```

### `src/{{PKG}}/infrastructure/tracking/run.py`

```python
"""Run handles — the per-run logging surface. ``RunHandle`` (real) + ``NullRun`` (no-op).

Every write is best-effort: a failure is warned and swallowed, never raised into the experiment.
"""

from __future__ import annotations

from contextlib import contextmanager
from pathlib import Path
from typing import TYPE_CHECKING, Any, Protocol, runtime_checkable

import structlog

if TYPE_CHECKING:
    from collections.abc import Iterator

from {{PKG}}.infrastructure.tracking.constants import (
    DEFAULT_REFERENCE_KEY,
    HASH_CHUNK_BYTES,
    REFERENCE_HASH_TAG_PREFIX,
    REFERENCE_TAG_PREFIX,
    RunStatus,
)

logger = structlog.get_logger(component="tracking.run")


@runtime_checkable
class Run(Protocol):
    """Per-run logging surface returned by ``track`` / ``create_run``."""

    def log_metric(self, key: str, value: float, step: int = 0) -> None: ...
    def log_metrics(self, metrics: dict[str, float], step: int = 0) -> None: ...
    def log_params(self, params: dict[str, Any]) -> None: ...
    def set_tag(self, key: str, value: str) -> None: ...
    def log_table(self, rows: list[dict[str, Any]], artifact_file: str) -> None: ...
    def log_json(self, obj: Any, artifact_file: str) -> None: ...
    def log_file(self, path: str, artifact_path: str | None = None) -> None: ...
    def log_reference(self, path: str, key: str | None = None) -> None: ...
    def span(self, name: str, inputs: dict[str, Any] | None = None) -> Any: ...
    def finish(self, status: str = RunStatus.FINISHED.value) -> None: ...

    @property
    def run_id(self) -> str: ...


class _RunOps(Protocol):
    """Low-level write primitives bound to a run; two impls (fluent vs client)."""

    def log_metric(self, run_id: str, key: str, value: float, step: int) -> None: ...
    def log_param(self, run_id: str, key: str, value: str) -> None: ...
    def set_tag(self, run_id: str, key: str, value: str) -> None: ...
    def log_dict(self, run_id: str, obj: Any, artifact_file: str) -> None: ...
    def log_table(self, run_id: str, rows: list[dict[str, Any]], artifact_file: str) -> None: ...
    def log_artifact(self, run_id: str, local_path: str, artifact_path: str | None) -> None: ...
    def start_span(self, name: str) -> Any: ...
    def set_terminated(self, run_id: str, status: str) -> None: ...


def _hash_file(path: Path) -> str | None:
    """Hex SHA-256 of a file in bounded chunks, or ``None``."""
    import hashlib

    digest = hashlib.sha256()
    try:
        with path.open("rb") as handle:
            for chunk in iter(lambda: handle.read(HASH_CHUNK_BYTES), b""):
                digest.update(chunk)
    except OSError:
        return None
    return digest.hexdigest()


class RunHandle:
    """A real MLflow run, writing through an injected ``_RunOps``."""

    def __init__(self, run_id: str, ops: _RunOps) -> None:
        self._run_id = run_id
        self._ops = ops

    @property
    def run_id(self) -> str:
        return self._run_id

    def log_metric(self, key: str, value: float, step: int = 0) -> None:
        try:
            self._ops.log_metric(self._run_id, key, value, step)
        except Exception:
            logger.warning("tracking_log_metric_failed", key=key, run_id=self._run_id)

    def log_metrics(self, metrics: dict[str, float], step: int = 0) -> None:
        for key, value in metrics.items():
            self.log_metric(key, value, step=step)

    def log_params(self, params: dict[str, Any]) -> None:
        for key, value in params.items():
            try:
                self._ops.log_param(self._run_id, key, str(value))
            except Exception:
                logger.warning("tracking_log_param_failed", key=key, run_id=self._run_id)

    def set_tag(self, key: str, value: str) -> None:
        try:
            self._ops.set_tag(self._run_id, key, value)
        except Exception:
            logger.warning("tracking_set_tag_failed", key=key, run_id=self._run_id)

    def log_table(self, rows: list[dict[str, Any]], artifact_file: str) -> None:
        try:
            self._ops.log_table(self._run_id, rows, artifact_file)
        except Exception:
            logger.warning("tracking_log_table_failed", file=artifact_file, run_id=self._run_id)

    def log_json(self, obj: Any, artifact_file: str) -> None:
        try:
            self._ops.log_dict(self._run_id, obj, artifact_file)
        except Exception:
            logger.warning("tracking_log_json_failed", file=artifact_file, run_id=self._run_id)

    def log_file(self, path: str, artifact_path: str | None = None) -> None:
        try:
            self._ops.log_artifact(self._run_id, path, artifact_path)
        except Exception:
            logger.warning("tracking_log_file_failed", path=path, run_id=self._run_id)

    def log_reference(self, path: str, key: str | None = None) -> None:
        ref_key = key if key is not None else DEFAULT_REFERENCE_KEY
        abs_path = str(Path(path).resolve())
        try:
            self._ops.set_tag(self._run_id, f"{REFERENCE_TAG_PREFIX}{ref_key}", abs_path)
            content_hash = _hash_file(Path(path))
            if content_hash is not None:
                self._ops.set_tag(self._run_id, f"{REFERENCE_HASH_TAG_PREFIX}{ref_key}", content_hash)
        except Exception:
            logger.warning("tracking_log_reference_failed", path=path, run_id=self._run_id)

    @contextmanager
    def span(self, name: str, inputs: dict[str, Any] | None = None) -> Iterator[Any]:
        try:
            span_cm = self._ops.start_span(name)
        except Exception:
            logger.warning("tracking_span_open_failed", name=name, run_id=self._run_id)
            yield None
            return
        span_obj = span_cm.__enter__()
        try:
            if inputs is not None and span_obj is not None:
                try:
                    span_obj.set_inputs(inputs)
                except Exception:
                    logger.warning("tracking_span_inputs_failed", name=name)
            yield span_obj
        except BaseException as exc:
            if not span_cm.__exit__(type(exc), exc, exc.__traceback__):
                raise
        else:
            span_cm.__exit__(None, None, None)

    def finish(self, status: str = RunStatus.FINISHED.value) -> None:
        try:
            self._ops.set_terminated(self._run_id, status)
        except Exception:
            logger.warning("tracking_finish_failed", status=status, run_id=self._run_id)


class NullRun:
    """No-op run used when tracking is disabled or MLflow is unavailable."""

    @property
    def run_id(self) -> str:
        return ""

    def log_metric(self, key: str, value: float, step: int = 0) -> None: ...
    def log_metrics(self, metrics: dict[str, float], step: int = 0) -> None: ...
    def log_params(self, params: dict[str, Any]) -> None: ...
    def set_tag(self, key: str, value: str) -> None: ...
    def log_table(self, rows: list[dict[str, Any]], artifact_file: str) -> None: ...
    def log_json(self, obj: Any, artifact_file: str) -> None: ...
    def log_file(self, path: str, artifact_path: str | None = None) -> None: ...
    def log_reference(self, path: str, key: str | None = None) -> None: ...

    @contextmanager
    def span(self, name: str, inputs: dict[str, Any] | None = None) -> Iterator[Any]:
        yield None

    def finish(self, status: str = RunStatus.FINISHED.value) -> None: ...


__all__ = ["NullRun", "Run", "RunHandle"]
```

### `src/{{PKG}}/infrastructure/tracking/tracker.py`

```python
"""Experiment tracker — vendor-neutral adapter over MLflow.

Protocol + MlflowTracker + NullTracker + factory. MLflow is lazy-imported and the whole toolkit
degrades, never blocks: if MLflow is absent or the server is unreachable the experiment runs against
NullTracker. track() = fluent (sequential); create_run()/open_run() = explicit run_id (parallel).
"""

from __future__ import annotations

from contextlib import contextmanager
from typing import TYPE_CHECKING, Any, Protocol, runtime_checkable

import structlog

from {{PKG}}.infrastructure.tracking.config import TrackingConfig
from {{PKG}}.infrastructure.tracking.constants import (
    AUTOLOG_STATUS_ENABLED,
    AUTOLOG_STATUS_SKIPPED_PREFIX,
    CONFIG_SNAPSHOT_ARTIFACT,
    PROMPT_ARTIFACT_FILE,
    PROMPT_ARTIFACT_PATH,
    TRACING_PARAM_PREFIX,
    RunStatus,
)
from {{PKG}}.infrastructure.tracking.provenance import Provenance, gather_provenance
from {{PKG}}.infrastructure.tracking.run import NullRun, Run, RunHandle, _RunOps

if TYPE_CHECKING:
    from collections.abc import Iterator

logger = structlog.get_logger(component="tracking.tracker")

_PARENT_RUN_ID_TAG = "mlflow.parentRunId"


def _rows_to_columns(rows: list[dict[str, Any]]) -> dict[str, list[Any]]:
    """Convert row dicts to MLflow's column-oriented table format (ragged-safe, None fill)."""
    columns: dict[str, list[Any]] = {}
    for row in rows:
        for key in row:
            if key not in columns:
                columns[key] = []
    for row in rows:
        for key in columns:
            columns[key].append(row.get(key))
    return columns


@runtime_checkable
class ExperimentTracker(Protocol):
    """Vendor-neutral experiment-tracking interface."""

    def track(
        self,
        stage: str,
        name: str,
        tags: dict[str, str] | None = None,
        params: dict[str, Any] | None = None,
        trace: bool = True,
        provenance: bool = True,
        prompt_text: str | None = None,
        config_snapshot: dict[str, Any] | None = None,
    ) -> Any: ...

    def create_run(
        self,
        stage: str,
        name: str,
        tags: dict[str, str] | None = None,
        params: dict[str, Any] | None = None,
        trace: bool = True,
        provenance: bool = True,
        parent_run_id: str | None = None,
        prompt_text: str | None = None,
        config_snapshot: dict[str, Any] | None = None,
    ) -> Run: ...

    def open_run(self, run_id: str) -> Run: ...
    def flush(self) -> None: ...


class _FluentRunOps:
    """``_RunOps`` backed by the fluent ``mlflow`` module (active run). Sequential only."""

    def __init__(self, mlflow_mod: Any) -> None:
        self._mlflow = mlflow_mod

    def log_metric(self, run_id: str, key: str, value: float, step: int) -> None:
        self._mlflow.log_metric(key, value, step=step)

    def log_param(self, run_id: str, key: str, value: str) -> None:
        self._mlflow.log_param(key, value)

    def set_tag(self, run_id: str, key: str, value: str) -> None:
        self._mlflow.set_tag(key, value)

    def log_dict(self, run_id: str, obj: Any, artifact_file: str) -> None:
        self._mlflow.log_dict(obj, artifact_file)

    def log_table(self, run_id: str, rows: list[dict[str, Any]], artifact_file: str) -> None:
        self._mlflow.log_table(_rows_to_columns(rows), artifact_file=artifact_file)

    def log_artifact(self, run_id: str, local_path: str, artifact_path: str | None) -> None:
        self._mlflow.log_artifact(local_path, artifact_path=artifact_path)

    def start_span(self, name: str) -> Any:
        return self._mlflow.start_span(name=name)

    def set_terminated(self, run_id: str, status: str) -> None:
        self._mlflow.end_run(status=status)


class _ClientRunOps:
    """``_RunOps`` backed by ``MlflowClient`` + explicit ``run_id``. Concurrency-safe."""

    def __init__(self, mlflow_mod: Any, client: Any) -> None:
        self._mlflow = mlflow_mod
        self._client = client

    def log_metric(self, run_id: str, key: str, value: float, step: int) -> None:
        self._client.log_metric(run_id, key, value, step=step)

    def log_param(self, run_id: str, key: str, value: str) -> None:
        self._client.log_param(run_id, key, value)

    def set_tag(self, run_id: str, key: str, value: str) -> None:
        self._client.set_tag(run_id, key, value)

    def log_dict(self, run_id: str, obj: Any, artifact_file: str) -> None:
        self._client.log_dict(run_id, obj, artifact_file)

    def log_table(self, run_id: str, rows: list[dict[str, Any]], artifact_file: str) -> None:
        self._client.log_table(run_id, data=_rows_to_columns(rows), artifact_file=artifact_file)

    def log_artifact(self, run_id: str, local_path: str, artifact_path: str | None) -> None:
        self._client.log_artifact(run_id, local_path, artifact_path=artifact_path)

    def start_span(self, name: str) -> Any:
        return self._mlflow.start_span(name=name)

    def set_terminated(self, run_id: str, status: str) -> None:
        self._client.set_terminated(run_id, status=status)


class MlflowTracker:
    """MLflow-backed experiment tracker (lazy import, degrade-don't-block)."""

    def __init__(self, config: TrackingConfig) -> None:
        self._config = config
        self._mlflow: Any = None
        self._available = False
        try:
            import mlflow  # type: ignore[import-not-found,unused-ignore]

            mlflow.set_tracking_uri(config.tracking_uri)
            self._mlflow = mlflow
            self._available = True
            logger.info("mlflow_tracker_initialized", tracking_uri=config.tracking_uri)
        except Exception:
            logger.warning("mlflow_unavailable_using_null", tracking_uri=config.tracking_uri)

    def _enable_autolog(self) -> dict[str, str]:
        status: dict[str, str] = {}
        for flavor in self._config.autolog_flavors:
            try:
                getattr(self._mlflow, flavor).autolog()
                status[flavor] = AUTOLOG_STATUS_ENABLED
            except Exception as exc:
                status[flavor] = f"{AUTOLOG_STATUS_SKIPPED_PREFIX}{type(exc).__name__}"
        return status

    def _merged_tags(self, tags: dict[str, str] | None) -> dict[str, str]:
        merged: dict[str, str] = dict(self._config.default_tags)
        if tags:
            merged.update(tags)
        return merged

    def _apply_provenance(
        self, run: Run, prompt_text: str | None, config_snapshot: dict[str, Any] | None
    ) -> None:
        prov: Provenance = gather_provenance(prompt_text=prompt_text, config_snapshot=config_snapshot)
        run.log_params(dict(prov.to_params()))
        if prov.config_snapshot is not None:
            run.log_json(prov.config_snapshot, CONFIG_SNAPSHOT_ARTIFACT)
        if prov.prompt_text is not None:
            run.log_json({"prompt": prov.prompt_text}, f"{PROMPT_ARTIFACT_PATH}/{PROMPT_ARTIFACT_FILE}")

    def _tracing_params(self, trace: bool) -> dict[str, str]:
        if not trace:
            return {}
        status = self._enable_autolog()
        return {f"{TRACING_PARAM_PREFIX}{flavor}": value for flavor, value in status.items()}

    @contextmanager
    def track(
        self,
        stage: str,
        name: str,
        tags: dict[str, str] | None = None,
        params: dict[str, Any] | None = None,
        trace: bool = True,
        provenance: bool = True,
        prompt_text: str | None = None,
        config_snapshot: dict[str, Any] | None = None,
    ) -> Iterator[Run]:
        if not self._available:
            yield NullRun()
            return
        try:
            self._mlflow.set_experiment(stage)
            run_ctx = self._mlflow.start_run(run_name=name)
            run_ctx.__enter__()
        except Exception:
            logger.warning("tracking_start_run_failed", stage=stage, name=name)
            yield NullRun()
            return

        ops: _RunOps = _FluentRunOps(self._mlflow)
        handle = RunHandle(run_id=self._safe_active_run_id(), ops=ops)
        self._prime_run(handle, tags, params, trace, provenance, prompt_text, config_snapshot)

        status = RunStatus.FINISHED.value
        try:
            yield handle
        except BaseException:
            status = RunStatus.FAILED.value
            self._finalize_fluent(status)
            raise
        else:
            self._finalize_fluent(status)

    def _finalize_fluent(self, status: str) -> None:
        self._maybe_flush()
        try:
            self._mlflow.end_run(status=status)
        except Exception:
            logger.warning("tracking_end_run_failed", status=status)

    def _safe_active_run_id(self) -> str:
        try:
            active = self._mlflow.active_run()
            run_id: str = active.info.run_id if active is not None else ""
            return run_id
        except Exception:
            return ""

    def create_run(
        self,
        stage: str,
        name: str,
        tags: dict[str, str] | None = None,
        params: dict[str, Any] | None = None,
        trace: bool = True,
        provenance: bool = True,
        parent_run_id: str | None = None,
        prompt_text: str | None = None,
        config_snapshot: dict[str, Any] | None = None,
    ) -> Run:
        if not self._available:
            return NullRun()
        try:
            from mlflow import MlflowClient  # type: ignore[import-not-found,unused-ignore]

            client = MlflowClient()
            experiment_id = self._get_or_create_experiment(client, stage)
            run = client.create_run(experiment_id, run_name=name)
            run_id: str = run.info.run_id
        except Exception:
            logger.warning("tracking_create_run_failed", stage=stage, name=name)
            return NullRun()

        ops: _RunOps = _ClientRunOps(self._mlflow, client)
        handle = RunHandle(run_id=run_id, ops=ops)
        self._prime_run(
            handle, tags, params, trace, provenance, prompt_text, config_snapshot, parent_run_id
        )
        return handle

    def open_run(self, run_id: str) -> Run:
        if not self._available:
            return NullRun()
        try:
            from mlflow import MlflowClient  # type: ignore[import-not-found,unused-ignore]

            client = MlflowClient()
        except Exception:
            logger.warning("tracking_open_run_failed", run_id=run_id)
            return NullRun()
        ops: _RunOps = _ClientRunOps(self._mlflow, client)
        return RunHandle(run_id=run_id, ops=ops)

    def _get_or_create_experiment(self, client: Any, stage: str) -> str:
        existing = client.get_experiment_by_name(stage)
        if existing is not None:
            experiment_id: str = existing.experiment_id
            return experiment_id
        created: str = client.create_experiment(stage)
        return created

    def _prime_run(
        self,
        handle: Run,
        tags: dict[str, str] | None,
        params: dict[str, Any] | None,
        trace: bool,
        provenance: bool,
        prompt_text: str | None,
        config_snapshot: dict[str, Any] | None,
        parent_run_id: str | None = None,
    ) -> None:
        for key, value in self._merged_tags(tags).items():
            handle.set_tag(key, value)
        if parent_run_id is not None:
            handle.set_tag(_PARENT_RUN_ID_TAG, parent_run_id)
        if params:
            handle.log_params(params)
        tracing_params = self._tracing_params(trace)
        if tracing_params:
            handle.log_params(dict(tracing_params))
        if provenance:
            self._apply_provenance(handle, prompt_text, config_snapshot)

    def _maybe_flush(self) -> None:
        if self._config.flush_on_exit:
            self.flush()

    def flush(self) -> None:
        if not self._available:
            return
        try:
            self._mlflow.flush_trace_async_logging()
        except Exception:
            logger.warning("tracking_flush_failed")


class NullTracker:
    """No-op tracker used when tracking is disabled or MLflow is absent."""

    @contextmanager
    def track(
        self,
        stage: str,
        name: str,
        tags: dict[str, str] | None = None,
        params: dict[str, Any] | None = None,
        trace: bool = True,
        provenance: bool = True,
        prompt_text: str | None = None,
        config_snapshot: dict[str, Any] | None = None,
    ) -> Iterator[Run]:
        yield NullRun()

    def create_run(
        self,
        stage: str,
        name: str,
        tags: dict[str, str] | None = None,
        params: dict[str, Any] | None = None,
        trace: bool = True,
        provenance: bool = True,
        parent_run_id: str | None = None,
        prompt_text: str | None = None,
        config_snapshot: dict[str, Any] | None = None,
    ) -> Run:
        return NullRun()

    def open_run(self, run_id: str) -> Run:
        return NullRun()

    def flush(self) -> None: ...


def get_tracker(config: TrackingConfig | None = None) -> ExperimentTracker:
    """Return a tracker: NullTracker when disabled, else MlflowTracker (which itself degrades)."""
    resolved = config if config is not None else TrackingConfig.from_env()
    if not resolved.enabled:
        return NullTracker()
    return MlflowTracker(resolved)


@contextmanager
def track(
    stage: str,
    name: str,
    tags: dict[str, str] | None = None,
    params: dict[str, Any] | None = None,
    trace: bool = True,
    provenance: bool = True,
    prompt_text: str | None = None,
    config_snapshot: dict[str, Any] | None = None,
    config: TrackingConfig | None = None,
) -> Iterator[Run]:
    """Fluent experiment-run context manager (sequential use)."""
    tracker = get_tracker(config)
    with tracker.track(
        stage=stage,
        name=name,
        tags=tags,
        params=params,
        trace=trace,
        provenance=provenance,
        prompt_text=prompt_text,
        config_snapshot=config_snapshot,
    ) as run:
        yield run
```

### `src/{{PKG}}/infrastructure/tracking/__init__.py`

```python
"""Generic experiment-tracking toolkit (MLflow-backed, degrade-don't-block)."""

from __future__ import annotations

from {{PKG}}.infrastructure.tracking.config import TrackingConfig
from {{PKG}}.infrastructure.tracking.provenance import Provenance, gather_provenance
from {{PKG}}.infrastructure.tracking.run import NullRun, Run, RunHandle
from {{PKG}}.infrastructure.tracking.tracker import (
    ExperimentTracker,
    MlflowTracker,
    NullTracker,
    get_tracker,
    track,
)

__all__ = [
    "ExperimentTracker",
    "MlflowTracker",
    "NullRun",
    "NullTracker",
    "Provenance",
    "Run",
    "RunHandle",
    "TrackingConfig",
    "gather_provenance",
    "get_tracker",
    "track",
]
```

## 4. Part C — optional dependency

Add MLflow as an **optional** extra (not a core dep — the toolkit lazy-imports it). In `pyproject.toml`:

```toml
[project.optional-dependencies]
tracking = [
    "mlflow>=3.13,<4",
    "pandas>=2.2,<4",   # only needed if you prefer DataFrame tables; the toolkit works without it
]
```

Install for clients with `uv sync --extra tracking` (or run scripts with `uv run --with mlflow ...`).
The toolkit also depends on `pydantic` and `structlog` (already core deps in most projects).

## 5. Part D — the skill + policy (so agents use it consistently)

Create these two files **under `.claude/`** — Claude Code reads skills from `.claude/skills/` and project
policy from `.claude/project/`. Do **not** put them under `.agents/` or a repo-root location. The skill is
auto-discovered and points at the policy so the top-level instruction files stay clean.

### `.claude/skills/experiment-tracking/SKILL.md`

````markdown
---
name: experiment-tracking
description: Use when running, tracking, benchmarking, sweeping, comparing, or evaluating any component or end-to-end experiment — e.g. "run a sweep", "benchmark these models/prompts", "compare A vs B", "track this calibration", "register this eval run". Triggers whenever an experiment produces params/metrics/output files that should be recorded and compared instead of dumped into ad-hoc folders.
---

# Experiment Tracking

Track every experiment with the `{{PKG}}.infrastructure.tracking` toolkit (MLflow-backed). Do not
hand-write MLflow plumbing or dump results into ad-hoc folders as the source of truth.

Policy & conventions: `.claude/project/tracking.md`.

## The one API (sequential / local)

```python
from {{PKG}}.infrastructure.tracking import track

with track(
    stage="<component>/<stage>",               # MLflow experiment = one per component/stage
    name="<variant>",                          # run name = the comparison grid
    tags={"study": "...", "model": "...", "prompt": "..."},
    params={"...": "..."},
    trace=True,        # autolog LLM calls (pydantic_ai/openai/litellm) for LLM experiments
    provenance=True,   # auto-log git sha/dirty/diff-hash/uv.lock-hash
) as run:
    run.log_metrics({"metric_name": 0.0})      # FLAT metric names (no "/")
    run.log_table(rows, "per_item.json")
    run.log_json(summary, "summary.json")
    run.log_file("report.html")
    run.log_reference("path/to/big.jsonl")     # zero-copy pointer + hash for large in-place files
    with run.span("step", inputs={...}):       # manual trace span; autolog spans nest inside
        ...
```

Tracking is best-effort: if MLflow/server is absent it degrades to a no-op and the experiment still runs.

## Parallel / concurrent

Fluent `track()` is not concurrency-safe. For concurrent sweeps use one OS process per model + the
explicit-`run_id` form: `get_tracker().create_run(stage, name, tags=..., parent_run_id=...)` then
`run.log_metrics(...); run.finish()`.

## Setup

- Server: the dockerised `mlflow-stack` — `docker compose -f {{INFRA_DIR}}/mlflow-stack/docker-compose.yml up -d`.
- `mlflow` is an optional extra: `uv run --with mlflow ...` or `uv sync --extra tracking`.
- Override the server via `MLFLOW_TRACKING_URI` or `config=TrackingConfig(...)`.

## Conventions

- One experiment per stage `<component>/<stage>`; one run per config/variant; the study goes in **tags**.
- **Tags = compare axis** (`study`, `prompt`, `model`, `dataset`, `sweep_id`, `run_level`); **params =
  reproducibility** (auto via `provenance=True`, plus your config). **Flat metric names.**

## Scope fence

Component experiments only. NOT: production LLM tracing, operational logs/metrics, or an end-to-end eval
framework — those keep their own tools.
````

### `.claude/project/tracking.md`

````markdown
# Experiment Tracking — policy

Durable conventions for the `{{PKG}}.infrastructure.tracking` toolkit. The workflow lives in the
`experiment-tracking` skill; this file holds the rules that must not drift.

## Rules

- **Use `track(...)`** for experiments; never hand-roll MLflow plumbing or treat ad-hoc folders as the
  durable source of truth.
- **One experiment per stage** `<component>/<stage>`; **one run per config/variant**; the study is a
  **tag** (`study`, `sweep_id`), never a new experiment.
- **Tags = compare axis**; **params = reproducibility** (`provenance=True` auto-logs git + lock hash).
- **Flat metric names** (`metric_f1`, not `metric/f1`).
- **`trace=True`** for LLM experiments. **Sequential → `track()`; concurrent → `create_run()` + one
  process per model** (fluent runs aren't concurrency-safe).
- **Best-effort:** tracking degrades to a no-op when MLflow is unavailable; it never blocks an experiment.

## Scope fence (hard boundary)

Component experiments only. MLflow must NOT own production LLM tracing (a dedicated tracer keeps that),
operational logs/metrics, an end-to-end eval framework, or any production hot path.

## Deployment & access

- Server = dockerised `mlflow-stack` (Postgres-backed, localhost-only `:5000`).
- Code = `src/{{PKG}}/infrastructure/tracking/`. MLflow is an optional extra (`uv sync --extra tracking`).
- **PII:** traces/tables can carry raw content — keep the server localhost-only; never put raw content or
  secrets in params/tags.
````

## 6. Verification (acceptance — run these; all must pass)

```bash
# code gates (toolkit imports fine WITHOUT mlflow installed)
uv run ruff format --check src/{{PKG}}/infrastructure/tracking/
uv run ruff check src/{{PKG}}/infrastructure/tracking/
uv run mypy --strict src/{{PKG}}/infrastructure/tracking/

# functional smoke (needs the server up + mlflow)
MLFLOW_TRACKING_URI=http://127.0.0.1:5000 uv run --with mlflow --with pandas python - <<'PY'
from {{PKG}}.infrastructure.tracking import track
with track("smoke/test", "r1", tags={"study": "s"}, params={"p": 1}, trace=False, provenance=True) as run:
    run.log_metrics({"acc": 0.9})
    run.log_json({"k": "v"}, "out.json")
    run.log_table([{"i": 1}, {"i": 2}], "t.json")
print("OK — check http://127.0.0.1:5000 → experiment 'smoke/test'")
PY
```

Add a unit test mirroring the toolkit's behaviour (pure logic + the degrade path always run; a real-mlflow
test guarded by `importlib.util.find_spec("mlflow")`). The key assertions: `NullRun`/`NullTracker` are
no-ops; `gather_provenance()` yields a git sha + dirty flag; `_rows_to_columns` aligns ragged rows;
`get_tracker(TrackingConfig(enabled=False))` returns a `NullTracker`; and (with mlflow) a real `track()`
records metrics/tags/params/artifacts.

## 7. Usage (how experiments use it)

```python
from {{PKG}}.infrastructure.tracking import track
with track("<component>/<stage>", "<variant>", tags={...}, trace=True, provenance=True) as run:
    run.log_metrics({"f1": 0.56}); run.log_table(rows, "x.json")
```

View/compare at **http://127.0.0.1:5000** → the experiment → add `prompt`/`model` tag columns or tick runs
→ **Compare** / Chart view; the **Traces** tab holds per-call LLM spans for traced runs.

## 8. Gotchas captured from the original adoption

- `mlflow.log_table` wants **column-oriented** data, not `list[dict]` — the `_rows_to_columns` helper
  handles that (don't pass a `list[dict]` straight through).
- MLflow 3.x **rejects the bare file store** by default ("maintenance mode") — use the **sqlite** or
  **Postgres** backend (the stack uses Postgres). For a throwaway file-store test set
  `MLFLOW_ALLOW_FILE_STORE=true`.
- The **official image lacks `psycopg2`** → the 2-line custom Dockerfile.
- **Traces don't migrate across backends** (they're tied to the store) — migrating runs carries
  metrics/params/artifacts but not old traces; live tracing works on the new backend.
- The MLflow 3.x **UI is GenAI-first**: classic Parameters/Metrics/Artifacts live on the run page but can
  be less prominent; metric columns must be added via the runs-table **Columns** control. (Use **flat**
  metric names so they show plainly.)
