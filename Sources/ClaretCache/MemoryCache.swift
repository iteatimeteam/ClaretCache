//
//  MemoryCache.swift
//  ClaretCache
//
//  Created by BirdMichael on 2019/7/23.
//  Copyright © 2019 com.ClaretCache. All rights reserved.
//

import Foundation

#if os(iOS) && canImport(UIKit)
import UIKit.UIApplication
#endif

public final class MemoryCache<Key, Value> where Key: Hashable {

    /// The name of the cache. **Default** is **"default"**
    var name: String = "default"

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

    #if os(iOS) && canImport(UIKit)
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
    var releaseOnMainThread: Bool = false

    /// If **YES**, the key-value pair will be released asynchronously to avoid blocking
    ///
    /// the access methods, otherwise it will be released in the access method
    /// (such as removeObjectForKey:). **Default is YES**.
    var releaseAsynchronously: Bool = true

    /// The number of objects in the cache (read-only)
    private(set) var totalCount: UInt = 0

    /// The total cost of objects in the cache (read-only).
    private(set) var totalCost: UInt = 0

    private var lock: pthread_mutex_t
    private let lru: LinkedMap<Key, Value> = LinkedMap<Key, Value>()
    private var queue: DispatchQueue

    public init() {
        self.lock = .init()
        pthread_mutex_init(&(self.lock), nil)
        self.queue = DispatchQueue(label: "com.iteatimeteam.ClaretCache.memory", qos: DispatchQoS.default)
        #if os(iOS) && canImport(UIKit)
        self.addNotification()
        #endif
    }

    deinit {
        pthread_mutex_destroy(&(self.lock))
        #if os(iOS) && canImport(UIKit)
        self.removeNotification()
        #endif
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
    final func contains(_ atKey: Key?) -> Bool {
        let node = lru.get(atKey)
        
        return node != nil
    }

    /// Sets the value of the specified key in the cache, and associates the key-value
    /// pair with the specified cost.
    /// - Parameter value: The object to store in the cache. If nil, it calls **remove(_ atKey:)**.
    /// - Parameter atKey: The atKey with which to associate the value. If nil, this method has no effect.
    /// - Parameter cost: The cost with which to associate the key-value pair.
    final func set(_ value: Value?, _ atKey: Key?, cost: UInt = 0) {
        // Delete new if value is nil
        // Cache if value is not nil
        guard let atKey = atKey else {
            
            return
        }
        
        guard let value = value else {
            
            remove(atKey)
            return
        }
        
        lru.put(atKey, value, cost: cost)
        
        if lru.totalCount > countLimit {
            
            trimTo(count: countLimit)
        }
        
        if lru.totalCost > costLimit {
            
            trimTo(cost: countLimit)
        }
    }

    /// Removes the value of the specified key in the cache.
    /// - Parameter atKey: atKey The atKey identifying the value to be removed.
    /// If nil, this method has no effect.
    final func remove(_ atKey: Key?) {
        lru.delete(atKey)
    }

    /// Empties the cache immediately.
    final func removeAll() {
        lru.deleteAll()
    }

    final subscript(_ atKey: Key?) -> Value? {
        get {
            return nil
        }
        set {
            self.set(newValue, atKey)
        }
    }

    /// Removes objects from the cache with LRU,
    /// until the **totalCount** is below or equal to the specified value.
    /// - Parameter count: The total count allowed to remain after the cache has been trimmed.
    final func trimTo(count: UInt) {
        self.trimCount(count)
    }

    /// Removes objects from the cache with LRU, until the **totalCost** is or equal to the specified value.
    /// - Parameter cost: cost The total cost allowed to remain after the cache has been trimmed.
    final func trimTo(cost: UInt) {
        self.trimCost(cost)
    }

    /// Removes objects from the cache with LRU, until all expiry objects removed by the specified value.
    /// - Parameter age: The maximum age (in seconds) of objects.
    final func trimTo(age: UInt) {
        self.trimAge(age)
    }
}

extension MemoryCache: CustomDebugStringConvertible {
    public var debugDescription: String {
        return "<\(type(of: self)): \(Unmanaged.passUnretained(self).toOpaque())> (\(self.name))"
    }
}

private extension MemoryCache {

    #if os(iOS) && canImport(UIKit)
    func addNotification() {

       let memoryWarningObserver = NotificationCenter.default.addObserver(forName: UIApplication.didReceiveMemoryWarningNotification ,object: nil, queue: nil) { [weak self] _ in
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

    final func trimCount(_ count: UInt) {
        while lru.totalCount > count {
            
            _ = lru.deleteTail()
        }
    }

    final func trimCost(_ cost: UInt) {
        while lru.totalCost > cost {
            
            _ = lru.deleteTail()
        }
    }

    final func trimAge(_ age: UInt) {

    }
}

/**
 A linked map used by MemoryCache.
 It's not thread-safe and does not validate the parameters.

 Typically, you should not use this class directly.
 */

fileprivate final class LinkedMap<Key, Value> where Key : Hashable {
    var dic: [Key:Node] = Dictionary<Key, Node<Key, Value>>.init()
    var totalCost: UInt = 0
    var totalCount: UInt = 0
    var head: Node<Key, Value>? // MRU, do not change it directly
    var tail: Node<Key, Value>? // LRU, do not change it directly
    var releaseOnMainThread: Bool = false
    var releaseAsynchronously: Bool = true

    fileprivate final class Node<Key, Value> : Equatable where Key : Hashable {
        var prev: Node?
        var next: Node?
        var key: Key
        var value: Value
        var cost: UInt = 0
        var time: TimeInterval = 0.0
        init(key: Key, value: Value, cost: UInt) {
            self.key = key
            self.value = value
            self.cost = cost
        }
        
        static func == (lhs: Node<Key, Value>, rhs: Node<Key, Value>) -> Bool {
            return lhs.key == rhs.key
        }
    }
    
    init() {

    }
    
    // MARK: -
    /// 从内存中查询key，如果有缓存存在，则返回。并将缓存移至最前。
    func get(_ key: Key?) -> Node<Key, Value>? {
        guard let key = key else {
            
            return nil
        }
        let dicNode = dic[key]
        if dicNode != nil {
            
            let prevDicNode = dicNode!.prev
            let nextDicNode = dicNode!.next
            nextDicNode?.prev = prevDicNode
            prevDicNode?.next = nextDicNode
            
            dicNode?.prev = nil
            dicNode?.next = head
            head?.prev = dicNode
            
            head = dicNode
        }
        
        return dicNode
    }
    
    func put(_ key: Key, _ value: Value, cost: UInt = 0) {
        let node = Node(key: key, value: value, cost: cost)
        let dicNode = get(key)
        if dicNode != nil {
            
            dic[key] = node
        } else {
            
            dic.updateValue(node, forKey: key)
            totalCount += 1
            totalCost += node.cost
        }
    }
    
    func delete(_ key: Key?) {
        guard let key = key else {
            
            return
        }
        guard let dicNode = dic[key] else {
            
            return
        }
        
        let prevDicNode = dicNode.prev
        let nextDicNode = dicNode.next
        if dicNode == head {
            
            head = nextDicNode
        } else if dicNode == tail {
            
            tail = prevDicNode
        }
        nextDicNode?.prev = prevDicNode
        prevDicNode?.next = nextDicNode
        dicNode.prev = nil
        dicNode.next = nil
        dic.removeValue(forKey: key)
        
        totalCount -= 1
        totalCost -= dicNode.cost
    }
    
    func deleteTail() -> Node<Key, Value>? {
        guard let tailNode = tail else {
            
            return nil
        }
        
        let prevTailNode = tailNode.prev
        
        tailNode.prev = nil
        tail = prevTailNode
        tail?.next = nil
        
        totalCount -= 1
        totalCost -= tailNode.cost
        
        return tailNode
    }
    
    func deleteAll() {
        var node = head
        while node != nil {
            let tempNode = node?.next
            node?.next = nil
            tempNode?.prev = nil
            node = tempNode
        }
        dic.removeAll()
        head = nil
        tail = nil
        
        totalCount = 0
        totalCost = 0
    }
}

extension LinkedMap {

    /// Insert a node at head and update the total cost.
    /// Node and node.key should not be nil.
    final func insert(atHead node: Node<Key, Value>) {

    }

    /// Bring a inner node to header.
    /// Node should already inside the dic.
    final func bring(toHead node: Node<Key, Value>) {

    }

    /// Remove a inner node and update the total cost.
    /// Node should already inside the dic.
    final func remove(_ node: Node<Key, Value>) {

    }

    /// Remove tail node if exist.
    final func removeTail() -> Node<Key, Value>? {
        let tempTail = tail
        return tempTail
    }

    /// Remove all node in background queue.
    final func removeAll() {

    }
}
