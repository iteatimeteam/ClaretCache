//
//  ClaretCacheDemoTests.swift
//  ClaretCacheDemoTests
//
//  Created by DearLan on 27/07/19.
//  Copyright © 2019 com.ClaretCache. All rights reserved.
//

import XCTest
@testable import ClaretCacheDemo

class ClaretCacheDemoTests: XCTestCase {

    let cache: MemoryCache<Int, Int> = MemoryCache<Int, Int>()

    override func setUp() {
        // Put setup code here. This method is called before the invocation of each test method in the class.
//        self.cache = MemoryCache<String, Int>()
    }

    override func tearDown() {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }

    func testInsert() {
        // This is an example of a functional test case.
        // Use XCTAssert and related functions to verify your tests produce the correct results.
        self.cache.countLimit = 800

        for idx in 1...1000 {
            self.cache[idx] = idx
        }

        assert(self.cache.totalCount == 800, "淘汰策略出错")
    }

    func testRead() {
        self.cache.removeAll()

        self.cache.countLimit = 800

        for idx in 1...1000 {
            self.cache[idx] = idx
        }
//        print("key: 1, value: \(self.cache[1] ?? -1)")
//        print("key: 888, value: \(self.cache[888] ?? -1)")
//        print("key: 777, value: \(self.cache[777] ?? -1)")
//        print("key: 999, value: \(self.cache[999] ?? -1)")
        assert(self.cache[1] == nil, "淘汰策略出错")
        assert((self.cache[888] ?? -1) == 888, "读取key为888,失败")
        assert((self.cache[777] ?? -1) == 777, "读取key为777,失败")
        assert((self.cache[999] ?? -1) == 999, "读取key为999,失败")
    }

//    func testPerformanceExample() {
//        // This is an example of a performance test case.
//        measure(metrics: [XCTCPUMetric()]) {
//            // Put the code whose CPU performance you want to measure here.
//            for idx in 1...100_000 {
//                self.cache[idx] = idx
//            }
//        }
//    }

}
