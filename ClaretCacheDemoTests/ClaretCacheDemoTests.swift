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
    var animal = Animal(name: "dawa", age: 3)
    let pathURL = URL.init(fileURLWithPath: NSHomeDirectory() + "/testKVStroage")
    var storage: KVStorage?
    override func setUp() {
        // Put setup code here. This method is called before the invocation of each test method in the class.
//        self.cache = MemoryCache<String, Int>()
        print(pathURL.absoluteString)
        guard let storage = KVStorage.init(path: pathURL, type: .mixed) else {
            assert(false, "KVStorage init error")
        }
        self.storage = storage
    }

    override func tearDown() {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }

    func testStorageInsert() {
        guard let storage = self.storage else {
            assert(false, "KVStorage init error")
        }
        do {
            let data = try NSKeyedArchiver.archivedData(withRootObject: animal, requiringSecureCoding: false)
            let item = KVStorageItem()
            item.key = "animal2"
            item.fileName = "image2"
            item.value = data
            guard storage.saveItem(item: item) else {
                return assert(false, "存储出错")
            }
        } catch {
            assert(false, "序列化出错")
        }
    }
    func testStorageQuery() {
        guard let storage = self.storage else {
            assert(false, "KVStorage init error")
        }
        if let data = storage.getItemForKey("animal")?.value {
            do {
                let loadAnimal = try NSKeyedUnarchiver.unarchivedObject(ofClasses: [Animal.self], from: data) as? Animal
                assert(animal.isEqual(loadAnimal), "KVStorage出错，存和取的不同")
            } catch {
                assert(false, "反序列化出错")
            }
        } else {
            assert(false, "KVStorage取出出错")
        }
        if let items = storage.getItemForKeys(["animal", "animal2"]), !items.isEmpty {
            items.forEach { (item) in
                if let data = item.value {
                    do {
                        let loadAnimal = try NSKeyedUnarchiver.unarchivedObject(ofClasses: [Animal.self], from: data) as? Animal
                        assert(animal.isEqual(loadAnimal), "KVStorage出错，存和取的不同")
                    } catch {
                        assert(false, "反序列化出错")
                    }
                } else {
                    assert(false, "KVStorage取出出错")
                }
            }
        } else {
            assert(false, "KVStorage取出出错")
        }
    }

    func testStorageRemove() {
        guard let storage = self.storage else {
            assert(false, "KVStorage init error")
        }
//        assert(storage.removeItems(keys: ["animal", "animal2"]), "remove error")
//        assert(storage.removeItemsToFitSize(93000), "removeItemsToFitSize error")
        assert(storage.removeItemsToFitCount(0), "removeItemsToFitCount error")
    }
    func testStorageGetItemInfo() {
        guard let storage = self.storage else {
            assert(false, "KVStorage init error")
        }
        print("itemExists=\(storage.itemExistsForKey("animal"))")
        print("getItemsCount=\(storage.getItemsCount())")
        print("getItemsSize=\(storage.getItemsSize())")
        if let item = storage.getItemInfoForKey("animal") {
            print("item.key=\(String(describing: item.key)), accessTime=\(item.accessTime), modifyTiem=\(item.modTime), fileName=\(String(describing: item.fileName))")
        } else {
            assert(false, "KVStorage取出出错")
        }
        if let items = storage.getItemInfoForKeys(["animal", "animal2"]), !items.isEmpty {
            items.forEach { (item) in
                print("item.key=\(String(describing: item.key)), accessTime=\(item.accessTime), modifyTiem=\(item.modTime), fileName=\(String(describing: item.fileName))")
            }
        } else {
            assert(false, "KVStorage取出出错")
        }
    }
    func testStorageGetItemValue() {
        guard let storage = self.storage else {
            assert(false, "KVStorage init error")
        }
        if let data = storage.getItemValueForKey("animal") {
            do {
                let loadAnimal = try NSKeyedUnarchiver.unarchivedObject(ofClasses: [Animal.self], from: data) as? Animal
                assert(animal.isEqual(loadAnimal), "KVStorage出错，存和取的不同")
            } catch {
                assert(false, "反序列化出错")
            }
        } else {
            assert(false, "KVStorage取出出错")
        }
        if let datas = storage.getItemValueForKeys(["animal", "animal2"]), !datas.isEmpty {
            datas.forEach { (_, data) in
                do {
                    let loadAnimal = try NSKeyedUnarchiver.unarchivedObject(ofClasses: [Animal.self], from: data) as? Animal
                    assert(animal.isEqual(loadAnimal), "KVStorage出错，存和取的不同")
                } catch {
                    assert(false, "反序列化出错")
                }
            }
        } else {
            assert(false, "KVStorage取出出错")
        }
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
