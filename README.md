This fork is based on the final source code of the now-discontinued Lime3DS emulator project.

It increases the UDP RPC memory-read payload from 32 to 1024 bytes, while preserving the
original 24-byte memory-write limit. This makes external RAM inspection substantially more
efficient without broadening the RPC server's write capability.

The original GPL-2.0-or-later license and notices are preserved. Modified source code remains
available in this public repository under the same terms.

If you are a user looking for a 3DS emulator. Please use [Azahar](https://github.com/azahar-emu/azahar), the successor to Lime3DS, instead.
