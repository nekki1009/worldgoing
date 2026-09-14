# Windows LFS clean guard

This repository's large, modified Blender files are repeatedly scanned by Git review.
Cancelling the upstream Git LFS 3.7.1 clean process can leave its temporary copy behind.
This Windows-only filter opens its temporary file with `DeleteOnClose`: Windows removes
the temporary name when the process exits, including forced termination. A hard link
publishes the complete, flushed SHA-256 object before its pointer is returned.

The original Git LFS client still parses existing pointers and performs smudge/downloads.
The guard supports Git's long-running filter v2 protocol and multiple requests. It honors
the active `lfs.storage` directory and refuses configured custom LFS extensions. Temporary
and object directories must support file hard links on the same local filesystem. This
deployment uses real directories on the same NTFS volume, outside Dropbox.

Build with the installed .NET 8 SDK; there are no external package dependencies:

```powershell
dotnet build tools/lfs-clean-guard/LfsCleanGuard.csproj -c Release
```

Use `verify.py` with a new, dedicated `--root` and the built executable as `--guard`.
Run `init`, `compatibility`, `interruption`, and `integration` in order. Tests use an
isolated Git repository with no remote, bounded child processes, byte comparisons to
upstream LFS, concurrent writes, forced termination, checkout, and error recovery.
Results identify all four runtime files by SHA-256, including the managed DLL.

`install.py --verified-root <test-root> --destination <new-local-directory>` verifies all
three PASS records against the build, copies that bundle outside the project, and changes
only this repository's `filter.lfs.clean` and `filter.lfs.process`. Existing smudge, required,
storage and global settings stay in place. The destination's `installation.json` records
the exact configuration to restore. It refuses unexpected existing filter overrides.

For the original standard configuration, rollback from this repository is:

```powershell
git config --local filter.lfs.clean 'git-lfs clean -- %f'
git config --local filter.lfs.process 'git-lfs filter-process'
```

Rolling back can bring the upstream interruption leak back. Re-running `git lfs install
--force` may also replace these overrides. The original object store, index and history
are not edited by the installer. Download temporaries remain owned by upstream LFS;
this guard addresses the observed **clean/upload preparation** copies. It does not add
a background service or periodic cleanup job.
