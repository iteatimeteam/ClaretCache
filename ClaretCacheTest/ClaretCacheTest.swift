//
//  ClaretCacheTest.swift
//  ClaretCacheTest
//
//  Created by king on 2019/7/24.
//  Copyright © 2019 com.ClaretCache. All rights reserved.
//

import XCTest
@testable import ClaretCacheDemo

class ClaretCacheTest: XCTestCase {

    override func setUp() {
        // Put setup code here. This method is called before the invocation of each test method in the class.
    }

    override func tearDown() {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }

    func testExample() {
        // This is an example of a functional test case.
        // Use XCTAssert and related functions to verify your tests produce the correct results.
        
        let cache = MemoryCache()
        
        print(cache)
    }

}
