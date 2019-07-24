//
//  MemoryCache.swift
//  ClaretCache
//
//  Created by BirdMichael on 2019/7/23.
//  Copyright © 2019 com.ClaretCache. All rights reserved.
//

import Foundation
import UIKit.UIApplication

/**
 A node in linked map.
 Typically, you should not use this class directly.
 */
class LinkedMapNode {
    private var prev: LinkedMapNode?
    private var next: LinkedMapNode?
    private var key: Any?
    private var value: Any?
    private var cost: UInt = 0
    private var time: TimeInterval = 0.0
}

/**
 A linked map used by MemoryCache.
 It's not thread-safe and does not validate the parameters.
 
 Typically, you should not use this class directly.
 */
class LinkedMap {
    private var dic: CFMutableDictionary
    private var totalCost: UInt = 0
    private var totalCount: UInt = 0
    private var head: LinkedMapNode? // MRU, do not change it directly
    private var tail: LinkedMapNode? // LRU, do not change it directly
    private var releaseOnMainThread: Bool = false
    private var releaseAsynchronously: Bool = true
    init() {
        var keyCallbacks = kCFTypeDictionaryKeyCallBacks
        var valueCallbacks = kCFTypeDictionaryValueCallBacks
        dic = CFDictionaryCreateMutable(kCFAllocatorDefault, 0, &keyCallbacks, &valueCallbacks)
    }
}

extension LinkedMap {
    /// Insert a node at head and update the total cost.
    /// Node and node.key should not be nil.
    func insert(atHead node: LinkedMapNode) {
    }
    /// Bring a inner node to header.
    /// Node should already inside the dic.
    func bring(toHead node: LinkedMapNode) {
    }
    /// Remove a inner node and update the total cost.
    /// Node should already inside the dic.
    func remove(_ node: LinkedMapNode) {
    }
    /// Remove tail node if exist.
    func removeTail() -> LinkedMapNode? {
        let tempTail = tail
        return tempTail
    }
    /// Remove all node in background queue.
    func removeAll() {
    }
}


public class MemoryCache {
    
    /// The name of the cache. **Default** is **"default"**
    public var name: String = "default"
    
    /// The maximum number of objects the cache should hold.
    ///
    ///  The default value is **UInt.max**, which means no limit.
    ///  This is not a strict limit—if the cache goes over the limit, some objects in the
    ///  cache could be evicted later in backgound thread.
    public var countLimit: UInt = UInt.max
    
    /// The maximum total cost that the cache can hold before it starts evicting objects.
    ///
    ///  The default value is **UInt.max**, which means no limit.
    /// This is not a strict limit—if the cache goes over the limit, some objects in the
    /// cache could be evicted later in backgound thread.
    public var costLimit: UInt = UInt.max
    
    /// The maximum expiry time of objects in cache.
    ///
    ///  The default value is **Double.greatestFiniteMagnitude**, which means no limit.
    ///  This is not a strict limit—if an object goes over the limit, the object could
    ///  be evicted later in backgound thread.
    public var ageLimit: TimeInterval = TimeInterval(Double.greatestFiniteMagnitude)
    
    /// The auto trim check time interval in seconds. **Default is 5.0**.
    ///
    ///  The cache holds an internal timer to check whether the cache reaches
    ///  its limits, and if the limit is reached, it begins to evict objects.
    public var autoTrimInterval: TimeInterval = 5.0
    
    /// If **YES**, the cache will remove all objects when the app receives a memory warning.
    /// The **default** value is **YES**.
    public var shouldRemoveAllObjectsOnMemoryWarning: Bool = true
    
    /// If **YES**, The cache will remove all objects when the app enter background.
    /// The **default** value is **YES**.
    public var shouldRemoveAllObjectsWhenEnteringBackground: Bool = true
    
    /// If **YES**, the key-value pair will be released on main thread, otherwise on background thread. **Default** is **NO**.
    ///
    /// You may set this value to **YES** if the key-value object contains
    /// **the instance which should be released in main thread (such as UIView/CALayer)**.
    public var releaseOnMainThread: Bool = false
    
    /// If **YES**, the key-value pair will be released asynchronously to avoid blocking
    ///
    /// the access methods, otherwise it will be released in the access method
    /// (such as removeObjectForKey:). **Default is YES**.
    public var releaseAsynchronously: Bool = true
    
    /// A closure to be executed when the app receives a memory warning.
    /// **The default value is nil**.
    public var didReceiveMemoryWarning: ((MemoryCache)->())? = nil
    
    /// A closure to be executed when the app enter background.
    /// **The default value is nil**.
    public var didEnterBackground: ((MemoryCache)->())? = nil
    
    /// The number of objects in the cache (read-only)
    public private(set) var totalCount: UInt = 0
    
    /// The total cost of objects in the cache (read-only).
    public private(set) var totalCost: UInt = 0

    private var lock: UnsafeMutablePointer<pthread_mutex_t>
    
    private let lru: LinkedMap = LinkedMap()
    
    private let queue: DispatchQueue = DispatchQueue(label: "com.ibireme.cache.memory", qos: DispatchQoS.default)
    
    public init() {
        let mutex = pthread_mutex_t()
        self.lock = UnsafeMutablePointer<pthread_mutex_t>.allocate(capacity: 1)
        self.lock.initialize(to: mutex)
        pthread_mutex_init(self.lock, nil)
        self.addNotification()
    }
    
    deinit {
        pthread_mutex_destroy(self.lock);
        self.lock.deinitialize(count: 1)
        self.removeNotification()
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
    func contains<K>(_ atKey: K?) -> Bool where K: Hashable {
        return false
    }
    
    /// Sets the value of the specified key in the cache, and associates the key-value
    /// pair with the specified cost.
    /// - Parameter object: The object to store in the cache. If nil, it calls **remove(_ atKey:)**.
    /// - Parameter atKey: The atKey with which to associate the value. If nil, this method has no effect.
    /// - Parameter cost: The cost with which to associate the key-value pair.
    func set<O, K>(_ object: O?, _ atKey: K?, cost: UInt = 0) where O: Any, K: Hashable  {
        // Delete new if object is nil
        // Cache if object is not nil
    }
    
    /// Removes the value of the specified key in the cache.
    /// - Parameter atKey: atKey The atKey identifying the value to be removed. If nil, this method has no effect.
    func remove<K>(_ atKey: K?) where K: Hashable {

    }
    
    /// Empties the cache immediately.
    func removeAll() {
        
    }
    
    subscript<O, K>(_ atKey: K?) -> O? where O: Any, K: Hashable {
        get {
            return nil
        }
        set {
            self.set(newValue, atKey)
        }
    }
    
    /// Removes objects from the cache with LRU, until the `totalCount` is below or equal to the specified value.
    /// - Parameter count: The total count allowed to remain after the cache has been trimmed.
    func trimTo(count: UInt) {
        self.trimCount(count)
    }
    
    /// Removes objects from the cache with LRU, until the `totalCost` is or equal to the specified value.
    /// - Parameter cost: cost The total cost allowed to remain after the cache has been trimmed.
    func trimTo(cost: UInt) {
        self.trimCost(cost)
    }
    
    /// Removes objects from the cache with LRU, until all expiry objects removed by the specified value.
    /// - Parameter age: The maximum age (in seconds) of objects.
    func trimTo(age: UInt) {
        self.trimAge(age)
    }
}

extension MemoryCache: CustomDebugStringConvertible {
    public var debugDescription: String {
        return "<\(type(of: self)): \(Unmanaged.passUnretained(self).toOpaque())> (\(self.name))"
    }
}

private extension MemoryCache {
    
    func addNotification() {
        NotificationCenter.default.addObserver(self, selector: #selector(MemoryCache.appDidReceiveMemoryWarningNotification), name: UIApplication.didReceiveMemoryWarningNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(MemoryCache.appDidEnterBackgroundNotification), name: UIApplication.didEnterBackgroundNotification, object: nil)
    }
    
    func removeNotification() {
        NotificationCenter.default.removeObserver(self, name: UIApplication.didReceiveMemoryWarningNotification, object: nil)
        NotificationCenter.default.removeObserver(self, name: UIApplication.didEnterBackgroundNotification, object: nil)
    }
    
    @objc
    func appDidReceiveMemoryWarningNotification()  {
        
    }
    
    @objc
    func appDidEnterBackgroundNotification()  {
            
    }
    
    func trimCount(_ count: UInt) {
        
    }
    
    func trimCost(_ cost: UInt) {
            
    }
    
    func trimAge(_ age: UInt) {
            
    }
}
