"""Port of Lunoir's main/mpv.ts. All media operations reach host/ and import mpv.

The Windows asyncio pipe transport uses overlapped I/O, so a pending read cannot
block a command write. Replies and event payloads use Lunoir's existing IPC shape.
"""
from __future__ import annotations

import asyncio
import contextlib
import json
import logging
import os
from pathlib import Path
import subprocess
import uuid

ROOT = Path(__file__).resolve().parent.parent
log = logging.getLogger(__name__)
OBSERVED = (
    "pause", "time-pos", "duration", "volume", "mute", "speed", "filename",
    "media-title", "metadata/by-key/uploader", "eof-reached", "ab-loop-a", "ab-loop-b",
    "seekable", "path", "chapter", "chapter-list", "video-params/aspect", "track-list",
    "aid", "sid", "audio-delay", "sub-delay", "sub-pos", "sub-scale", "container-fps",
    "estimated-frame-count", "estimated-frame-number", "video-params/gamma",
    "video-params/w", "video-params/h", "audio-codec-name", "audio-params/channel-count",
)


class MpvError(RuntimeError):
    pass


_job = None


def tie_to_this_process(pid: int) -> None:
    """Put a child (vmpv-host, flet.exe) in a kill-on-close job, so Windows ends it
    whenever this Python process ends, including crashes and kills that skip close()."""
    global _job
    try:
        import win32api, win32con, win32job
        if _job is None:
            job = win32job.CreateJobObject(None, "")
            info = win32job.QueryInformationJobObject(job, win32job.JobObjectExtendedLimitInformation)
            info["BasicLimitInformation"]["LimitFlags"] |= win32job.JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE
            win32job.SetInformationJobObject(job, win32job.JobObjectExtendedLimitInformation, info)
            _job = job  # held until the process exits; closing it kills the hosts
        handle = win32api.OpenProcess(win32con.PROCESS_SET_QUOTA | win32con.PROCESS_TERMINATE, False, pid)
        try:
            win32job.AssignProcessToJobObject(_job, handle)
        finally:
            win32api.CloseHandle(handle)
    except Exception:
        log.warning("could not tie process %s to this process", pid, exc_info=True)


class MpvController:
    def __init__(self, log_directory: Path | None = None) -> None:
        self.log_directory = log_directory
        self.process: subprocess.Popen | None = None
        self.writer: asyncio.StreamWriter | None = None
        self.reader_task: asyncio.Task | None = None
        self.pending: dict[int, asyncio.Future] = {}
        self.events: asyncio.Queue[dict] = asyncio.Queue()
        self.request_id = 0
        self.closing = False
        self.log = None

    async def start(self, wid: int | None = None, extra_args: list[str] | None = None,
                    observe: bool = True) -> None:
        executable = ROOT / "flet_lunoir/runtime/vmpv-host.exe"
        if not executable.is_file():
            raise MpvError("The V backend has not been built. Run build-flet.ps1 first.")
        pipe = rf"\\.\pipe\lunoir-v-{os.getpid()}-{uuid.uuid4().hex}"
        args = [str(executable), "--no-config", "--idle=yes", "--keep-open=yes",
                "--no-osc", "--no-osd-bar", "--vo=gpu-next", "--hwdec=auto",
                "--volume-max=150", "--input-default-bindings=no", "--input-vo-keyboard=no",
                "--input-cursor=no", "--terminal=no", f"--input-ipc-server={pipe}"]
        if wid is not None:
            args.append(f"--wid={wid}")
        args.extend(extra_args or [])
        log_dir = self.log_directory or Path(os.environ.get("LOCALAPPDATA", ROOT)) / "Lunoir V"
        log_dir.mkdir(parents=True, exist_ok=True)
        self.log = (log_dir / "backend.log").open("ab")
        self.process = subprocess.Popen(
            args, cwd=executable.parent, stdin=subprocess.DEVNULL,
            stdout=subprocess.DEVNULL, stderr=self.log,
            creationflags=subprocess.CREATE_NO_WINDOW,
        )
        tie_to_this_process(self.process.pid)
        loop = asyncio.get_running_loop()
        reader = asyncio.StreamReader(limit=4 * 1024 * 1024)
        protocol = asyncio.StreamReaderProtocol(reader)
        try:
            for _ in range(100):
                if self.process.poll() is not None:
                    raise MpvError(f"The V backend exited ({self.process.returncode}); see {log_dir / 'backend.log'}.")
                try:
                    transport, _ = await loop.create_pipe_connection(lambda: protocol, pipe)
                    self.writer = asyncio.StreamWriter(transport, protocol, reader, loop)
                    break
                except OSError:
                    await asyncio.sleep(0.05)
            else:
                raise MpvError("Timed out connecting to the V backend.")
            self.reader_task = asyncio.create_task(self._read_loop(reader))
            for index, name in enumerate(OBSERVED if observe else (), 1):
                await self.command("observe_property", index, name)
        except BaseException:
            await self.close()
            raise

    async def command(self, *args):
        if self.writer is None or self.writer.is_closing():
            raise MpvError("The V backend is disconnected.")
        self.request_id += 1
        request_id = self.request_id
        future = asyncio.get_running_loop().create_future()
        self.pending[request_id] = future
        payload = json.dumps({"command": list(args), "request_id": request_id}, ensure_ascii=False)
        try:
            self.writer.write((payload + "\n").encode("utf-8"))
            await self.writer.drain()
            return await asyncio.wait_for(future, 5)
        finally:
            self.pending.pop(request_id, None)

    async def set(self, name: str, value) -> None:
        await self.command("set_property", name, value)

    async def _read_loop(self, reader: asyncio.StreamReader) -> None:
        reason = "The V backend disconnected."
        try:
            while line := await reader.readline():
                try:
                    message = json.loads(line)
                except (ValueError, UnicodeError):
                    continue
                if "event" in message:
                    self.events.put_nowait(message)
                elif future := self.pending.pop(message.get("request_id"), None):
                    if not future.done():
                        if message.get("error", "success") == "success":
                            future.set_result(message.get("data"))
                        else:
                            future.set_exception(MpvError(message["error"]))
        except (OSError, ValueError) as error:
            reason = str(error)
        finally:
            for future in list(self.pending.values()):
                if not future.done():
                    future.set_exception(MpvError(reason))
            self.pending.clear()
            if not self.closing:
                self.events.put_nowait({"event": "backend-error", "error": reason})

    async def close(self) -> None:
        self.closing = True
        if self.writer:
            with contextlib.suppress(Exception):
                await self.command("quit")
            self.writer.close()
            with contextlib.suppress(Exception):
                await self.writer.wait_closed()
            self.writer = None
        if self.process:
            try:
                await asyncio.wait_for(asyncio.to_thread(self.process.wait), 3)
            except asyncio.TimeoutError:
                self.process.kill()
                await asyncio.to_thread(self.process.wait)
            self.process = None
        if self.reader_task:
            self.reader_task.cancel()
            with contextlib.suppress(asyncio.CancelledError):
                await self.reader_task
            self.reader_task = None
        if self.log:
            self.log.close()
            self.log = None
