//
//  MemoryCache.swift
//  ClaretCache
//
//  Created by BirdMichael on 2019/7/23.
//  Copyright © 2019 com.ClaretCache. All rights reserved.
//

import Foundation

#if canImport(UIKit)
import UIKit.UIApplication
#endif

#if canImport(QuartzCore)
import QuartzCore.CABase
#endif

public final class MemoryCache<Key, Value> where Key: Hashable, Value: Equatable {

    /// The name of the cache. **Default** is **"com.iteatimeteam.ClaretCache.memory.default"**
    let name: String

    /// The maximum number of objects the cache should hold.
    ///
    ///  The default value is **UInt.max**, which means no limit.
    ///  This is not a strict limit—if the cache goes over the limit, some objects in the
    ///  cache could be evicted later in backgound thread.
    var countLimit: UInt = UInt.max

    /// The maximum total cost that the cache can hold before it starts evicting objects.
    ///
    ///  The default value is **UInt.max**, which means no limit.
    /// This is not a strict limit—if the cache goes over the limit, some objects in the
    /// cache could be evicted later in backgound thread.
    var costLimit: UInt = UInt.max

    /// The maximum expiry time of objects in cache.
    ///
    ///  The default value is **Double.greatestFiniteMagnitude**, which means no limit.
    ///  This is not a strict limit—if an object goes over the limit, the object could
    ///  be evicted later in backgound thread.
    var ageLimit: TimeInterval = TimeInterval(Double.greatestFiniteMagnitude)

    /// The auto trim check time interval in seconds. **Default is 5.0**.
    ///
    ///  The cache holds an internal timer to check whether the cache reaches
    ///  its limits, and if the limit is reached, it begins to evict objects.
    var autoTrimInterval: TimeInterval = 5.0

    #if canImport(UIKit)
    /// If **YES**, the cache will remove all objects when the app receives a memory warning.
    /// The **default** value is **YES**.
    var removeAllObjectsOnMemoryWarning: Bool = true

    /// If **YES**, The cache will remove all objects when the app enter background.
    /// The **default** value is **YES**.
    var removeAllObjectsWhenEnteringBackground: Bool = true

    /// A closure to be executed when the app receives a memory warning.
    /// **The default value is nil**.
    var didReceiveMemoryWarning: ((MemoryCache) -> Void)?

    /// A closure to be executed when the app enter background.
    /// **The default value is nil**.
    var didEnterBackground: ((MemoryCache) -> Void)?

    private var observers: [NSObjectProtocol] = []
    #endif

    /// If **YES**, the key-value pair will be released on main thread, otherwise on background thread.
    /// **Default** is **NO**.
    ///
    /// You may set this value to **YES** if the key-value object contains
    /// **the instance which should be released in main thread (such as UIView/CALayer)**.
    var releaseOnMainThread: Bool {
        set {
            self.lock {
                self.lru.releaseOnMainThread = newValue
            }
       }
       get {
            return self.lockRead { self.lru.releaseOnMainThread }
       }
    }

    /// If **YES**, the key-value pair will be released asynchronously to avoid blocking
    ///
    /// the access methods, otherwise it will be released in the access method
    /// (such as removeObjectForKey:). **Default is YES**.
    var releaseAsynchronously: Bool {
        set {
            self.lock {
                self.lru.releaseAsynchronously = newValue
            }
        }
        get {
            return self.lockRead { self.lru.releaseAsynchronously }
        }
    }

    /// The number of objects in the cache (read-only)
    var totalCount: UInt {
        return self.lockRead { self.lru.totalCount }
    }

    /// The total cost of objects in the cache (read-only).
    var totalCost: UInt {
        return self.lockRead { self.lru.totalCost }
    }

    private var mutex: pthread_mutex_t
    private let lru: LinkedMap<Key, Value> = LinkedMap<Key, Value>()
    private var queue: DispatchQueue

    /// The constructor
    /// - Parameter name: The name of the cache.
    /// The default value is **"com.iteatimeteam.ClaretCache.memory.default"**
    /// - Parameter costLimit: The maximum total cost that the cache can hold before it starts evicting objects.
    /// The default value is **UInt.max**, which means no limit.
    /// - Parameter countLimit: The maximum number of objects the cache should hold.
    /// The default value is **UInt.max**, which means no limit.
    /// - Parameter ageLimit: The maximum expiry time of objects in cache.
    /// The default value is **Double.greatestFiniteMagnitude**, which means no limit.
    /// - Parameter autoTrimInterval: The auto trim check time interval in seconds.
    /// The default value is **5.0**.
    init(name: String = "com.iteatimeteam.ClaretCache.memory.default",
         costLimit: UInt = UInt.max,
         countLimit: UInt = UInt.max,
         ageLimit: TimeInterval = TimeInterval(Double.greatestFiniteMagnitude),
         autoTrimInterval: TimeInterval = 5.0) {
        self.name = name
        self.costLimit = costLimit
        self.countLimit = countLimit
        self.ageLimit = ageLimit
        self.autoTrimInterval = autoTrimInterval

        self.mutex = .init()
        pthread_mutex_init(&(self.mutex), nil)
        self.queue = DispatchQueue(label: "com.iteatimeteam.ClaretCache.memory", qos: DispatchQoS.default)
        #if canImport(UIKit)
        self.addNotification()
        #endif
        self.trimRecursively()
    }

    deinit {
        #if canImport(UIKit)
        self.removeNotification()
        #endif
        self.lru.removeAll()
        pthread_mutex_destroy(&(self.mutex))
    }
}

// MARK: - Access Methods
///=============================================================================
/// @name Access Methods
///=============================================================================
public extension MemoryCache {

    /// Returns a Boolean value that indicates whether a given key is in cache.
    /// - Parameter atKey: atKey An object identifying the value. If nil, just return **NO**.
    /// - Returns: Whether the atKey is in cache.
    final func contains(_ atKey: Key) -> Bool {
        return self.lockRead { self.lru.dic[atKey] != nil }
    }

    /// Sets the value of the specified key in the cache, and associates the key-value
    /// pair with the specified cost.
    /// - Parameter value: The object to store in the cache. If nil, it calls **remove(_ atKey:)**.
    /// - Parameter atKey: The atKey with which to associate the value. If nil, this method has no effect.
    /// - Parameter cost: The cost with which to associate the key-value pair.
    final func set(_ value: Value?, _ atKey: Key, cost: UInt = 0) {
        // Delete new if value is nil
        // Cache if value is not nil
        guard let value = value else {
            self.remove(atKey)
            return
        }
        self.lock {
            let now = currentTime()
            if let node = self.lru.dic[atKey] {
                self.lru.totalCost -= node.cost
                self.lru.totalCount += cost
                node.cost = cost
                node.time = now
                node.value = value
                self.lru.bring(toHead: node)
            } else {
                let node = LinkedMap<Key, Value>.Node<Key, Value>(atKey: atKey, value: value, cost: cost)
                node.time = now
                self.lru.insert(atHead: node)
            }

            if self.lru.totalCost > self.costLimit {
                self.queue.async {
                    self.trimTo(cost: self.costLimit)
                }
            }

            if self.lru.totalCount > self.countLimit {
                if let node = self.lru.removeTail() {
                    self.release {
                        //hold and release in queue
                        _ = node.cost
                    }
                }
            }
        }
    }

    /// Removes the value of the specified key in the cache.
    /// - Parameter atKey: atKey The atKey identifying the value to be removed.
    /// If nil, this method has no effect.
    final func remove(_ atKey: Key) {
        pthread_mutex_lock(&(self.mutex))
        defer {
            pthread_mutex_unlock(&(self.mutex))
        }
        guard let node = self.lru.dic[atKey] else { return }
        self.lru.remove(node)
        self.release {
            _ = node.cost //hold and release in queue
        }
    }

    /// Empties the cache immediately.
    final func removeAll() {
        lock {
            self.lru.removeAll()
        }
    }

    final subscript(_ atKey: Key) -> Value? {
        get {
            return lockRead { () -> Value? in
                guard let node = self.lru.dic[atKey] else {
                    return nil
                }
                node.time = currentTime()
                self.lru.bring(toHead: node)
                return node.value
            }
        }
        set {
            self.set(newValue, atKey)
        }
    }

    /// Removes objects from the cache with LRU,
    /// until the **totalCount** is below or equal to the specified value.
    /// - Parameter count: The total count allowed to remain after the cache has been trimmed.
    final func trimTo(count: UInt) {
        guard count > .zero else {
            self.removeAll()
            return
        }

        self.trimCount(count)
    }

    /// Removes objects from the cache with LRU, until the **totalCost** is or equal to the specified value.
    /// - Parameter cost: cost The total cost allowed to remain after the cache has been trimmed.
    final func trimTo(cost: UInt) {
        self.trimCost(cost)
    }

    /// Removes objects from the cache with LRU, until all expiry objects removed by the specified value.
    /// - Parameter age: The maximum age (in seconds) of objects.
    final func trimTo(age: TimeInterval) {
        self.trimAge(age)
    }
}

extension MemoryCache: CustomDebugStringConvertible {
    public var debugDescription: String {
        return "<\(type(of: self)): \(Unmanaged.passUnretained(self).toOpaque())> (\(self.name))"
    }
}

private extension MemoryCache {

    #if canImport(UIKit)
    func addNotification() {

       let memoryWarningObserver = NotificationCenter.default.addObserver(forName: UIApplication.didReceiveMemoryWarningNotification, object: nil, queue: nil) { [weak self] _ in
            guard let self = self else { return }
            self.didReceiveMemoryWarning?(self)
            if self.removeAllObjectsOnMemoryWarning {
                self.removeAll()
            }
        }

        let enterBackgroundObserver = NotificationCenter.default.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: nil) { [weak self] _ in
            guard let self = self else { return }
            self.didEnterBackground?(self)
            if self.removeAllObjectsWhenEnteringBackground {
                self.removeAll()
            }
        }
        self.observers.append(contentsOf: [memoryWarningObserver, enterBackgroundObserver])
    }

    func removeNotification() {
        self.observers.forEach {
            NotificationCenter.default.removeObserver($0)
        }
        self.observers.removeAll()
    }
    #endif

    final func trimLRU(path: KeyPath<LinkedMap<Key, Value>, UInt>, limit: UInt) {

        var finish = self.lockRead { () -> Bool in
            if limit == .zero {
                self.lru.removeAll()
                return true
            } else if self.lru[keyPath: path] <= limit {
                return true
            } else {
                return false
            }
        }
        guard !finish else { return }

        var holder: [LinkedMap<Key, Value>.Node<Key, Value>] = []

        while !finish {
            if pthread_mutex_trylock(&(self.mutex)) == .zero {
                if self.lru[keyPath: path] > limit {
                    if let node = self.lru.removeTail() {
                        holder.append(node)
                    }
                } else {
                    finish = true
                }
                pthread_mutex_unlock(&(self.mutex))
            } else {
                usleep(10 * 1000) //10 ms
            }
        }

        guard !holder.isEmpty else { return }

        self.release(trimed: true) {
            _ = holder.isEmpty // release in queue
        }
    }

    final func trimCost(_ costLimit: UInt) {
        self.trimLRU(path: \.totalCost, limit: costLimit)
    }

    final func trimCount(_ countLimit: UInt) {
        self.trimLRU(path: \.totalCount, limit: countLimit)
    }

    final func trimAge(_ ageLimit: TimeInterval) {
        let now = currentTime()
        var finish = self.lockRead { () -> Bool in
            if ageLimit == .zero {
                self.lru.removeAll()
                return true
            } else if self.lru.tail != nil || (now - (self.lru.tail?.time ?? 0)) <= ageLimit {
                return  true
            } else {
                return false
            }
        }
        guard !finish else { return }

        var holder: [LinkedMap<Key, Value>.Node<Key, Value>] = []

        while !finish {
            if pthread_mutex_trylock(&(self.mutex)) == .zero {
                if let tail = self.lru.tail, (now - tail.time) > ageLimit {
                    if let node = self.lru.removeTail() {
                        holder.append(node)
                    }
                } else {
                    finish = true
                }
                pthread_mutex_unlock(&(self.mutex))
            } else {
                usleep(10 * 1000) //10 ms
            }
        }

        guard !holder.isEmpty else { return }

        self.release(trimed: true) {
            _ = holder.isEmpty // release in queue
        }
    }

    final func trimRecursively() {
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + self.autoTrimInterval) { [weak self] in
            guard let self = self else { return }
            self.trimInBackground()
            self.trimRecursively()
        }
    }

    final func trimInBackground() {
        self.queue.async { [weak self] in
            guard let self = self else { return }
            self.trimTo(cost: self.costLimit)
            self.trimTo(count: self.countLimit)
            self.trimTo(age: self.ageLimit)
        }
    }

    final func lock(execute: (() -> Void)) {
        pthread_mutex_lock(&(self.mutex))
        defer {
            pthread_mutex_unlock(&(self.mutex))
        }
        execute()
    }

    final func lockRead<V>(execute: (() -> V)) -> V {
        pthread_mutex_lock(&(self.mutex))
        defer {
            pthread_mutex_unlock(&(self.mutex))
        }
        return execute()
    }

    final func release(trimed: Bool = false, _ execute: @escaping (() -> Void)) {
        if trimed {
            let queue = self.lru.releaseOnMainThread ? DispatchQueue.main : memoryCacheReleaseQueue()
            queue.async(execute: execute)
        } else {
            if self.lru.releaseAsynchronously {
                let queue = self.lru.releaseAsynchronously ? DispatchQueue.main : memoryCacheReleaseQueue()
                queue.async(execute: execute)
            } else if self.lru.releaseOnMainThread && pthread_main_np() != .zero {
                DispatchQueue.main.async(execute: execute)
            }
        }
    }

    final func currentTime() -> TimeInterval {
        #if canImport(QuartzCore)
        return CACurrentMediaTime()
        #else
        return Date().timeIntervalSince1970
        #endif
    }
}

private func memoryCacheReleaseQueue() -> DispatchQueue {
    return DispatchQueue.global(qos: .utility)
}

/**
 A linked map used by MemoryCache.
 It's not thread-safe and does not validate the parameters.

 Typically, you should not use this class directly.
 */
fileprivate final class LinkedMap<Key, Value> where Key: Hashable, Value: Equatable {
    var dic: [Key: Node<Key, Value>] = [:]
    var totalCost: UInt = 0
    var totalCount: UInt = 0
    var head: Node<Key, Value>? // MRU, do not change it directly
    var tail: Node<Key, Value>? // LRU, do not change it directly
    var releaseOnMainThread: Bool = false
    var releaseAsynchronously: Bool = true

    final class Node<Key, Value>: Equatable where Key: Hashable, Value: Equatable {
        var prev: Node?
        var next: Node?
        var key: Key!
        var value: Value?
        var cost: UInt = 0
        var time: TimeInterval = 0.0

       convenience init(atKey: Key, value: Value?, cost: UInt = 0) {
            self.init()
            self.key = atKey
            self.value = value
            self.cost = cost
        }

        static func == (lhs: Node<Key, Value>, rhs: Node<Key, Value>) -> Bool {
            return lhs.key == rhs.key && lhs.value == rhs.value
        }
    }
}

extension LinkedMap {

    /// Insert a node at head and update the total cost.
    /// Node and node.key should not be nil.
    final func insert(atHead node: Node<Key, Value>) {
        self.dic[node.key] = node
        self.totalCost += node.cost
        self.totalCount += 1
        if self.head != nil {
            node.next = self.head
            self.head?.prev = node
            self.head = node
        } else {
            self.tail = node
            self.head = self.tail
        }
    }

    /// Bring a inner node to header.
    /// Node should already inside the dic.
    final func bring(toHead node: Node<Key, Value>) {
        guard self.head == node else { return }
        if let tail = self.tail, tail == node {
            self.tail = node.prev
            self.tail?.next = nil
        } else {
            node.next?.prev = node.prev
            node.prev?.next = node.next
        }

        node.next = self.head
        node.prev = nil
        self.head?.prev = node
        self.head = node
    }

    /// Remove a inner node and update the total cost.
    /// Node should already inside the dic.
    final func remove(_ node: Node<Key, Value>) {
        self.dic.removeValue(forKey: node.key)
        self.totalCost -= node.cost
        self.totalCount -= 1

        if node.next != nil {
            node.next?.prev = node.prev
        }

        if node.prev != nil {
            node.prev?.next = node.next
        }

        if self.head == node {
            self.head = node.next
        }

        if self.tail == node {
            self.tail = node.prev
        }
    }

    /// Remove tail node if exist.
    final func removeTail() -> Node<Key, Value>? {
        guard let tail = self.tail else { return nil }
        self.dic.removeValue(forKey: tail.key)
        self.totalCost -= tail.cost
        self.totalCount -= 1
        if self.head == tail {
            self.head = nil
            self.tail = nil
        } else {
            self.tail = tail.prev
            self.tail?.next = nil
        }
        return tail
    }

    /// Remove all node in background queue.
    final func removeAll() {
        self.totalCost = 0
        self.totalCount = 0
        self.head = nil
        self.tail = nil
        guard !self.dic.isEmpty else { return }

        let holder: [Key: Node<Key, Value>] = self.dic
        self.dic = [:]
        if self.releaseAsynchronously {
            let queue = self.releaseOnMainThread ? DispatchQueue.main : memoryCacheReleaseQueue()
            queue.async {
                // hold and release in specified queue
               _ = holder.count
            }
        } else if self.releaseOnMainThread && pthread_main_np() != .zero {
            DispatchQueue.main.async {
                // hold and release in specified queue
                _ = holder.count
            }
        } else {
            // nothing
        }
    }
}
