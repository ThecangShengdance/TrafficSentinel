import Darwin

struct InterfaceCounters: Equatable {
    var rx: UInt64 = 0
    var tx: UInt64 = 0
}

struct RawCounters: Equatable {
    var interfaces: [String: InterfaceCounters] = [:]

    var rx: UInt64 {
        interfaces.values.reduce(0) { $0 &+ $1.rx }
    }

    var tx: UInt64 {
        interfaces.values.reduce(0) { $0 &+ $1.tx }
    }

    var total: UInt64 { rx &+ tx }

    /// 按接口分别求增量，避免某个接口加入 / 离开时把它的历史累计值误当成新流量。
    func delta(from previous: RawCounters) -> (rx: UInt64, tx: UInt64) {
        var rxDelta: UInt64 = 0
        var txDelta: UInt64 = 0
        for (name, current) in interfaces {
            guard let old = previous.interfaces[name] else { continue }
            if current.rx >= old.rx { rxDelta &+= current.rx - old.rx }
            if current.tx >= old.tx { txDelta &+= current.tx - old.tx }
        }
        return (rxDelta, txDelta)
    }
}

/// 读取系统累计收发字节数。
///
/// 使用 `NET_RT_IFLIST2` 拿到 64 位计数（不会像 `if_data` 那样在 4 GB 处回绕），
/// 只统计 `en*`（Wi-Fi、有线、iPhone USB 共享）与 `pdp_ip*`（蜂窝）接口，
/// 避免把 loopback、VPN（utun）、AirDrop（awdl）等重复计算进去。
enum NetworkCounters {
    static func read() -> RawCounters {
        if let counters = readSysctl() {
            return counters
        }
        return readGetifaddrs() ?? RawCounters()
    }

    // MARK: - sysctl (64-bit)

    private static func readSysctl() -> RawCounters? {
        var mib: [Int32] = [CTL_NET, PF_ROUTE, 0, 0, NET_RT_IFLIST2, 0]
        var length = 0
        guard sysctl(&mib, 6, nil, &length, nil, 0) == 0, length > 0 else { return nil }

        var buffer = [UInt8](repeating: 0, count: length)
        guard sysctl(&mib, 6, &buffer, &length, nil, 0) == 0, length > 0 else { return nil }

        var counters = RawCounters()
        buffer.withUnsafeBytes { raw in
            var offset = 0
            while offset + MemoryLayout<if_msghdr>.size <= length {
                let header = raw.loadUnaligned(fromByteOffset: offset, as: if_msghdr.self)
                let messageLength = Int(header.ifm_msglen)
                guard messageLength > 0, offset + messageLength <= length else { break }

                if Int32(header.ifm_type) == RTM_IFINFO2,
                   offset + MemoryLayout<if_msghdr2>.size <= length {
                    let info = raw.loadUnaligned(fromByteOffset: offset, as: if_msghdr2.self)
                    var nameBuffer = [CChar](repeating: 0, count: 32)
                    if if_indextoname(UInt32(info.ifm_index), &nameBuffer) != nil {
                        let name = String(cString: nameBuffer)
                        if isCounted(name) {
                            counters.interfaces[name] = InterfaceCounters(
                                rx: info.ifm_data.ifi_ibytes,
                                tx: info.ifm_data.ifi_obytes
                            )
                        }
                    }
                }
                offset += messageLength
            }
        }
        return counters
    }

    // MARK: - getifaddrs fallback (32-bit)

    private static func readGetifaddrs() -> RawCounters? {
        var addressList: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&addressList) == 0, let first = addressList else { return nil }
        defer { freeifaddrs(addressList) }

        var counters = RawCounters()
        for pointer in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let entry = pointer.pointee
            guard let address = entry.ifa_addr,
                  address.pointee.sa_family == UInt8(AF_LINK),
                  let dataPointer = entry.ifa_data else { continue }
            let name = String(cString: entry.ifa_name)
            guard isCounted(name) else { continue }
            let data = dataPointer.assumingMemoryBound(to: if_data.self).pointee
            counters.interfaces[name] = InterfaceCounters(
                rx: UInt64(data.ifi_ibytes),
                tx: UInt64(data.ifi_obytes)
            )
        }
        return counters
    }

    private static func isCounted(_ interfaceName: String) -> Bool {
        interfaceName.hasPrefix("en") || interfaceName.hasPrefix("pdp_ip")
    }
}
