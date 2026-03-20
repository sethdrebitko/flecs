// OsApi.swift - 1:1 translation of flecs os_api.h
// Operating system abstraction API for Flecs

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#endif


public typealias ecs_os_thread_t = UInt
public typealias ecs_os_cond_t = UInt
public typealias ecs_os_mutex_t = UInt
public typealias ecs_os_dl_t = UInt
public typealias ecs_os_sock_t = UInt
public typealias ecs_os_thread_id_t = UInt64
public typealias ecs_os_proc_t = @convention(c) () -> Void


public struct ecs_time_t {
    public var sec: UInt32 = 0
    public var nanosec: UInt32 = 0
    public init() {}
    public init(sec: UInt32, nanosec: UInt32) {
        self.sec = sec
        self.nanosec = nanosec
    }
}


public typealias ecs_os_api_init_t = @convention(c) () -> Void
public typealias ecs_os_api_fini_t = @convention(c) () -> Void
public typealias ecs_os_api_malloc_t = @convention(c) (ecs_size_t) -> UnsafeMutableRawPointer?
public typealias ecs_os_api_free_t = @convention(c) (UnsafeMutableRawPointer?) -> Void
public typealias ecs_os_api_realloc_t = @convention(c) (UnsafeMutableRawPointer?, ecs_size_t) -> UnsafeMutableRawPointer?
public typealias ecs_os_api_calloc_t = @convention(c) (ecs_size_t) -> UnsafeMutableRawPointer?
public typealias ecs_os_api_strdup_t = @convention(c) (UnsafePointer<CChar>?) -> UnsafeMutablePointer<CChar>?
public typealias ecs_os_thread_callback_t = @convention(c) (UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer?
public typealias ecs_os_api_thread_new_t = @convention(c) (ecs_os_thread_callback_t?, UnsafeMutableRawPointer?) -> ecs_os_thread_t
public typealias ecs_os_api_thread_join_t = @convention(c) (ecs_os_thread_t) -> UnsafeMutableRawPointer?
public typealias ecs_os_api_thread_self_t = @convention(c) () -> ecs_os_thread_id_t
public typealias ecs_os_api_ainc_t = @convention(c) (UnsafeMutablePointer<Int32>) -> Int32
public typealias ecs_os_api_lainc_t = @convention(c) (UnsafeMutablePointer<Int64>) -> Int64
public typealias ecs_os_api_mutex_new_t = @convention(c) () -> ecs_os_mutex_t
public typealias ecs_os_api_mutex_lock_t = @convention(c) (ecs_os_mutex_t) -> Void
public typealias ecs_os_api_mutex_unlock_t = @convention(c) (ecs_os_mutex_t) -> Void
public typealias ecs_os_api_mutex_free_t = @convention(c) (ecs_os_mutex_t) -> Void
public typealias ecs_os_api_cond_new_t = @convention(c) () -> ecs_os_cond_t
public typealias ecs_os_api_cond_free_t = @convention(c) (ecs_os_cond_t) -> Void
public typealias ecs_os_api_cond_signal_t = @convention(c) (ecs_os_cond_t) -> Void
public typealias ecs_os_api_cond_broadcast_t = @convention(c) (ecs_os_cond_t) -> Void
public typealias ecs_os_api_cond_wait_t = @convention(c) (ecs_os_cond_t, ecs_os_mutex_t) -> Void
public typealias ecs_os_api_sleep_t = @convention(c) (Int32, Int32) -> Void
public typealias ecs_os_api_enable_high_timer_resolution_t = @convention(c) (Bool) -> Void
public typealias ecs_os_api_get_time_t = @convention(c) (UnsafeMutablePointer<ecs_time_t>?) -> Void
public typealias ecs_os_api_now_t = @convention(c) () -> UInt64
public typealias ecs_os_api_log_t = @convention(c) (Int32, UnsafePointer<CChar>?, Int32, UnsafePointer<CChar>?) -> Void
public typealias ecs_os_api_abort_t = @convention(c) () -> Void
public typealias ecs_os_api_dlopen_t = @convention(c) (UnsafePointer<CChar>?) -> ecs_os_dl_t
public typealias ecs_os_api_dlproc_t = @convention(c) (ecs_os_dl_t, UnsafePointer<CChar>?) -> ecs_os_proc_t?
public typealias ecs_os_api_dlclose_t = @convention(c) (ecs_os_dl_t) -> Void
public typealias ecs_os_api_module_to_path_t = @convention(c) (UnsafePointer<CChar>?) -> UnsafeMutablePointer<CChar>?


public struct ecs_os_api_t {
    // API init and deinit
    public var init_: ecs_os_api_init_t? = nil
    public var fini_: ecs_os_api_fini_t? = nil

    // Memory management
    public var malloc_: ecs_os_api_malloc_t? = nil
    public var realloc_: ecs_os_api_realloc_t? = nil
    public var calloc_: ecs_os_api_calloc_t? = nil
    public var free_: ecs_os_api_free_t? = nil

    // Strings
    public var strdup_: ecs_os_api_strdup_t? = nil

    // Threads
    public var thread_new_: ecs_os_api_thread_new_t? = nil
    public var thread_join_: ecs_os_api_thread_join_t? = nil
    public var thread_self_: ecs_os_api_thread_self_t? = nil

    // Tasks
    public var task_new_: ecs_os_api_thread_new_t? = nil
    public var task_join_: ecs_os_api_thread_join_t? = nil

    // Atomic increment and decrement
    public var ainc_: ecs_os_api_ainc_t? = nil
    public var adec_: ecs_os_api_ainc_t? = nil
    public var lainc_: ecs_os_api_lainc_t? = nil
    public var ladec_: ecs_os_api_lainc_t? = nil

    // Mutex
    public var mutex_new_: ecs_os_api_mutex_new_t? = nil
    public var mutex_free_: ecs_os_api_mutex_free_t? = nil
    public var mutex_lock_: ecs_os_api_mutex_lock_t? = nil
    public var mutex_unlock_: ecs_os_api_mutex_lock_t? = nil

    // Condition variable
    public var cond_new_: ecs_os_api_cond_new_t? = nil
    public var cond_free_: ecs_os_api_cond_free_t? = nil
    public var cond_signal_: ecs_os_api_cond_signal_t? = nil
    public var cond_broadcast_: ecs_os_api_cond_broadcast_t? = nil
    public var cond_wait_: ecs_os_api_cond_wait_t? = nil

    // Time
    public var sleep_: ecs_os_api_sleep_t? = nil
    public var now_: ecs_os_api_now_t? = nil
    public var get_time_: ecs_os_api_get_time_t? = nil

    // Logging
    public var log_: ecs_os_api_log_t? = nil

    // Application termination
    public var abort_: ecs_os_api_abort_t? = nil

    // Dynamic library loading
    public var dlopen_: ecs_os_api_dlopen_t? = nil
    public var dlproc_: ecs_os_api_dlproc_t? = nil
    public var dlclose_: ecs_os_api_dlclose_t? = nil

    // Module paths
    public var module_to_dl_: ecs_os_api_module_to_path_t? = nil
    public var module_to_etc_: ecs_os_api_module_to_path_t? = nil

    // Logging state
    public var log_level_: Int32 = -1
    public var log_indent_: Int32 = 0
    public var log_last_error_: Int32 = 0
    public var log_last_timestamp_: Int64 = 0

    // Flags
    public var flags_: ecs_flags32_t = 0

    // File used for logging output
    public var log_out_: UnsafeMutableRawPointer? = nil

    public init() {}
}


public var ecs_os_api = ecs_os_api_t()


public var ecs_os_api_malloc_count: Int64 = 0
public var ecs_os_api_realloc_count: Int64 = 0
public var ecs_os_api_calloc_count: Int64 = 0
public var ecs_os_api_free_count: Int64 = 0


public func ecs_os_malloc(_ size: ecs_size_t) -> UnsafeMutableRawPointer? {
    if let fn = ecs_os_api.malloc_ {
        return fn(size)
    }
    return malloc(Int(size))
}

public func ecs_os_free(_ ptr: UnsafeMutableRawPointer?) {
    if let fn = ecs_os_api.free_ {
        fn(ptr)
        return
    }
    free(ptr)
}

public func ecs_os_realloc(_ ptr: UnsafeMutableRawPointer?, _ size: ecs_size_t) -> UnsafeMutableRawPointer? {
    if let fn = ecs_os_api.realloc_ {
        return fn(ptr, size)
    }
    return realloc(ptr, Int(size))
}

public func ecs_os_calloc(_ size: ecs_size_t) -> UnsafeMutableRawPointer? {
    if let fn = ecs_os_api.calloc_ {
        return fn(size)
    }
    return calloc(1, Int(size))
}

public func ecs_os_strdup(_ str: UnsafePointer<CChar>?) -> UnsafeMutablePointer<CChar>? {
    guard let str = str else { return nil }
    if let fn = ecs_os_api.strdup_ {
        return fn(str)
    }
    return strdup(str)
}

public func ecs_os_memdup(_ src: UnsafeRawPointer?, _ size: ecs_size_t) -> UnsafeMutableRawPointer? {
    guard let src = src, size > 0 else { return nil }
    let dst = ecs_os_malloc(size)
    if let dst = dst {
        memcpy(dst, src, Int(size))
    }
    return dst
}

// Typed allocation macros (mirrors C ecs_os_malloc_t, ecs_os_calloc_t, etc.)

@inline(__always)
public func ecs_os_malloc_t<T>(_ type: T.Type) -> UnsafeMutablePointer<T>? {
    return ecs_os_malloc(ecs_size_t(MemoryLayout<T>.stride))?.assumingMemoryBound(to: T.self)
}

@inline(__always)
public func ecs_os_malloc_n<T>(_ type: T.Type, _ count: Int32) -> UnsafeMutablePointer<T>? {
    return ecs_os_malloc(ecs_size_t(MemoryLayout<T>.stride) * count)?.assumingMemoryBound(to: T.self)
}

@inline(__always)
public func ecs_os_calloc_t<T>(_ type: T.Type) -> UnsafeMutablePointer<T>? {
    return ecs_os_calloc(ecs_size_t(MemoryLayout<T>.stride))?.assumingMemoryBound(to: T.self)
}

@inline(__always)
public func ecs_os_calloc_n<T>(_ type: T.Type, _ count: Int32) -> UnsafeMutablePointer<T>? {
    return ecs_os_calloc(ecs_size_t(MemoryLayout<T>.stride) * count)?.assumingMemoryBound(to: T.self)
}

@inline(__always)
public func ecs_os_realloc_n<T>(_ ptr: UnsafeMutableRawPointer?, _ type: T.Type, _ count: Int32) -> UnsafeMutablePointer<T>? {
    return ecs_os_realloc(ptr, ecs_size_t(MemoryLayout<T>.stride) * count)?.assumingMemoryBound(to: T.self)
}

@inline(__always)
public func ecs_os_free_t<T>(_ ptr: UnsafeMutablePointer<T>?) {
    ecs_os_free(UnsafeMutableRawPointer(ptr))
}

// Memory operation macros (mirrors C ecs_os_memcpy, ecs_os_memset, etc.)

@inline(__always)
public func ecs_os_memcpy(_ dst: UnsafeMutableRawPointer?, _ src: UnsafeRawPointer?, _ num: Int) {
    memcpy(dst, src, num)
}

@inline(__always)
public func ecs_os_memset(_ ptr: UnsafeMutableRawPointer?, _ value: Int32, _ num: Int) {
    memset(ptr, value, num)
}

@inline(__always)
public func ecs_os_memcpy_t<T>(_ dst: UnsafeMutableRawPointer?, _ src: UnsafeRawPointer?, _ type: T.Type) {
    memcpy(dst, src, MemoryLayout<T>.stride)
}

@inline(__always)
public func ecs_os_memcpy_n<T>(_ dst: UnsafeMutableRawPointer?, _ src: UnsafeRawPointer?, _ type: T.Type, _ count: Int) {
    memcpy(dst, src, MemoryLayout<T>.stride * count)
}

@inline(__always)
public func ecs_os_memset_t<T>(_ ptr: UnsafeMutableRawPointer?, _ value: Int32, _ type: T.Type) {
    memset(ptr, value, MemoryLayout<T>.stride)
}

@inline(__always)
public func ecs_os_memset_n<T>(_ ptr: UnsafeMutableRawPointer?, _ value: Int32, _ type: T.Type, _ count: Int) {
    memset(ptr, value, MemoryLayout<T>.stride * count)
}

@inline(__always)
public func ecs_os_zeromem<T>(_ ptr: UnsafeMutablePointer<T>?) {
    if ptr != nil {
        memset(UnsafeMutableRawPointer(ptr), 0, MemoryLayout<T>.stride)
    }
}

// OS API initialization

public func ecs_os_set_api_defaults() {
    // Set default implementations using C standard library
    // Memory
    ecs_os_api.malloc_ = { size in malloc(Int(size)) }
    ecs_os_api.realloc_ = { ptr, size in realloc(ptr, Int(size)) }
    ecs_os_api.calloc_ = { size in calloc(1, Int(size)) }
    ecs_os_api.free_ = { ptr in free(ptr) }
    ecs_os_api.strdup_ = { str in
        guard let str = str else { return nil }
        return strdup(str)
    }

    // Abort
    ecs_os_api.abort_ = { abort() }

    // Logging
    ecs_os_api.log_ = { level, file, line, msg in
        guard let msg = msg else { return }
        let msgStr = String(cString: msg)
        if level >= 0 {
            print("[trace] \(msgStr)")
        } else if level == -2 {
            print("[warn] \(msgStr)")
        } else if level == -3 {
            print("[error] \(msgStr)")
        } else if level == -4 {
            print("[fatal] \(msgStr)")
        }
    }

    // Time
    ecs_os_api.now_ = {
        var tv = timeval()
        gettimeofday(&tv, nil)
        return UInt64(tv.tv_sec) * 1_000_000_000 + UInt64(tv.tv_usec) * 1000
    }

    ecs_os_api.get_time_ = { time_out in
        guard let time_out = time_out else { return }
        var tv = timeval()
        gettimeofday(&tv, nil)
        time_out.pointee.sec = UInt32(tv.tv_sec)
        time_out.pointee.nanosec = UInt32(tv.tv_usec) * 1000
    }

    ecs_os_api.sleep_ = { sec, nanosec in
        var ts = timespec()
        ts.tv_sec = Int(sec)
        ts.tv_nsec = Int(nanosec)
        nanosleep(&ts, nil)
    }

    ecs_os_api.log_level_ = -1
}

public func ecs_os_init() {
    if ecs_os_api.malloc_ == nil {
        ecs_os_set_api_defaults()
    }
    if let initFn = ecs_os_api.init_ {
        initFn()
    }
}

public func ecs_os_fini() {
    if let finiFn = ecs_os_api.fini_ {
        finiFn()
    }
}

public func ecs_os_set_api(_ api: UnsafePointer<ecs_os_api_t>) {
    ecs_os_api = api.pointee
}

public func ecs_os_get_api() -> ecs_os_api_t {
    return ecs_os_api
}


public func ecs_time_measure(_ start: UnsafeMutablePointer<ecs_time_t>) -> Double {
    var stop = ecs_time_t()
    ecs_os_api.get_time?(&stop)

    var result = Double(stop.sec) - Double(start.pointee.sec)
    result += (Double(stop.nanosec) - Double(start.pointee.nanosec)) / 1_000_000_000.0

    start.pointee = stop
    return result
}

public func ecs_time_to_double(_ t: ecs_time_t) -> Double {
    return Double(t.sec) + Double(t.nanosec) / 1_000_000_000.0
}


public func ecs_os_dbg(_ file: UnsafePointer<CChar>?, _ line: Int32, _ msg: UnsafePointer<CChar>?) {
    ecs_os_api.log_?(1, file, line, msg)
}

public func ecs_os_trace(_ file: UnsafePointer<CChar>?, _ line: Int32, _ msg: UnsafePointer<CChar>?) {
    ecs_os_api.log_?(0, file, line, msg)
}

public func ecs_os_warn(_ file: UnsafePointer<CChar>?, _ line: Int32, _ msg: UnsafePointer<CChar>?) {
    ecs_os_api.log_?(-2, file, line, msg)
}

public func ecs_os_err(_ file: UnsafePointer<CChar>?, _ line: Int32, _ msg: UnsafePointer<CChar>?) {
    ecs_os_api.log_?(-3, file, line, msg)
}

public func ecs_os_fatal(_ file: UnsafePointer<CChar>?, _ line: Int32, _ msg: UnsafePointer<CChar>?) {
    ecs_os_api.log_?(-4, file, line, msg)
}


public func ecs_os_abort() {
    if let fn = ecs_os_api.abort_ {
        fn()
    }
    abort()
}


public func ecs_os_thread_new(_ callback: ecs_os_thread_callback_t?, _ param: UnsafeMutableRawPointer?) -> ecs_os_thread_t {
    return ecs_os_api.thread_new_?(callback, param) ?? 0
}

public func ecs_os_thread_join(_ thread: ecs_os_thread_t) -> UnsafeMutableRawPointer? {
    return ecs_os_api.thread_join_?(thread)
}

public func ecs_os_thread_self() -> ecs_os_thread_id_t {
    return ecs_os_api.thread_self_?() ?? 0
}


public func ecs_os_mutex_new() -> ecs_os_mutex_t {
    return ecs_os_api.mutex_new_?() ?? 0
}

public func ecs_os_mutex_free(_ mutex: ecs_os_mutex_t) {
    ecs_os_api.mutex_free_?(mutex)
}

public func ecs_os_mutex_lock(_ mutex: ecs_os_mutex_t) {
    ecs_os_api.mutex_lock_?(mutex)
}

public func ecs_os_mutex_unlock(_ mutex: ecs_os_mutex_t) {
    ecs_os_api.mutex_unlock_?(mutex)
}


public func ecs_os_cond_new() -> ecs_os_cond_t {
    return ecs_os_api.cond_new_?() ?? 0
}

public func ecs_os_cond_free(_ cond: ecs_os_cond_t) {
    ecs_os_api.cond_free_?(cond)
}

public func ecs_os_cond_signal(_ cond: ecs_os_cond_t) {
    ecs_os_api.cond_signal_?(cond)
}

public func ecs_os_cond_broadcast(_ cond: ecs_os_cond_t) {
    ecs_os_api.cond_broadcast_?(cond)
}

public func ecs_os_cond_wait(_ cond: ecs_os_cond_t, _ mutex: ecs_os_mutex_t) {
    ecs_os_api.cond_wait_?(cond, mutex)
}


public func ecs_os_ainc(_ value: UnsafeMutablePointer<Int32>) -> Int32 {
    if let fn = ecs_os_api.ainc_ {
        return fn(value)
    }
    value.pointee += 1
    return value.pointee
}

public func ecs_os_adec(_ value: UnsafeMutablePointer<Int32>) -> Int32 {
    if let fn = ecs_os_api.adec_ {
        return fn(value)
    }
    value.pointee -= 1
    return value.pointee
}

public func ecs_os_lainc(_ value: UnsafeMutablePointer<Int64>) -> Int64 {
    if let fn = ecs_os_api.lainc_ {
        return fn(value)
    }
    value.pointee += 1
    return value.pointee
}

public func ecs_os_ladec(_ value: UnsafeMutablePointer<Int64>) -> Int64 {
    if let fn = ecs_os_api.ladec_ {
        return fn(value)
    }
    value.pointee -= 1
    return value.pointee
}


public func ecs_os_inc(_ v: UnsafeMutablePointer<Int32>) {
    v.pointee += 1
}

public func ecs_os_dec(_ v: UnsafeMutablePointer<Int32>) {
    v.pointee -= 1
}

public func ecs_os_linc(_ v: UnsafeMutablePointer<Int64>) {
    v.pointee += 1
}

public func ecs_os_ldec(_ v: UnsafeMutablePointer<Int64>) {
    v.pointee -= 1
}


public func ecs_os_sleep(_ sec: Int32, _ nanosec: Int32) {
    ecs_os_api.sleep_?(sec, nanosec)
}


public let EcsOsApiHighResolutionTimer: ecs_flags32_t = (1 << 0)
public let EcsOsApiLogWithColors: ecs_flags32_t = (1 << 1)
public let EcsOsApiLogWithTimeStamp: ecs_flags32_t = (1 << 2)
public let EcsOsApiLogWithTimeDelta: ecs_flags32_t = (1 << 3)
