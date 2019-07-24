//
//  MemoryCache.swift
//  ClaretCache
//
//  Created by BirdMichael on 2019/7/23.
//  Copyright © 2019 com.ClaretCache. All rights reserved.
//

import Foundation

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
