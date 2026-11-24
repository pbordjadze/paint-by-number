// Foundation on Android does not re-export the C library, whose overlay carries the
// Float and CGFloat overloads of the math functions (cos, sin, …) that Glibc and Darwin give.
#if os(Android)
@_exported import Android
#endif
