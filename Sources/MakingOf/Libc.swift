// The C library: its math (cos, sin, …, with the Float overloads) comes with Foundation on Apple
// platforms and Linux, but off Apple platforms this module imports FoundationEssentials, which
// re-exports no C library (Portability.swift), and Foundation on Android doesn't re-export it either.
#if os(Android)
@_exported import Android
#elseif canImport(Glibc)
@_exported import Glibc
#endif
