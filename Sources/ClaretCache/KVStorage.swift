//
//  KVStorage.swift
//  ClaretCacheDemo
//
//  Created by HZheng on 2019/7/28.
//  Copyright © 2019 com.ClaretCache. All rights reserved.
//

import Foundation
import SQLite3

#if canImport(UIKit)
import UIKit.UIApplication
#endif

var isAppExtension: Bool = {
    return Bundle.main.bundleURL.pathExtension == "appex"
}()

public enum KVStorageType {
    case file
    case sqlite
    case mixed
}

/**
 KVStorageItem is used by `KVStorage` to store key-value pair and meta data.
 Typically, you should not use this class directly.
 */
public class KVStorageItem {
    var key: String?            ///< key
    var value: Data?            ///< value
    var fileName: String?       ///< fileName (nil if inline)
    var size: Int = 0           ///< value's size in bytes
    var modTime: Int = 0        ///< modification unix timestamp
    var accessTime: Int = 0     ///< last access unix timestamp
    var extendedData: Data?     ///< extended data (nil if no extended data)
}

/*
 File:
 /path/
 /manifest.sqlite
 /manifest.sqlite-shm
 /manifest.sqlite-wal
 /data/
 /e10adc3949ba59abbe56e057f20f883e
 /e10adc3949ba59abbe56e057f20f883e
 /trash/
 /unused_file_or_folder
 
 SQL:
 create table if not exists manifest (
 key                 text,
 filename            text,
 size                integer,
 inline_data         blob,
 modification_time   integer,
 last_access_time    integer,
 extended_data       blob,
 primary key(key)
 );
 create index if not exists last_access_time_idx on manifest(last_access_time);
 */

public class KVStorage {
    fileprivate let kMaxErrorRetryCount = 8
    fileprivate let kMinRetryTimeInterval = 2.0
    fileprivate let kPathLengthMax = PATH_MAX - 64
    fileprivate let kDBFileName = "manifest.sqlite"
    fileprivate let kDBShmFileName = "manifest.sqlite-shm"
    fileprivate let kDBWalFileName = "manifest.sqlite-wal"
    fileprivate let kDataDirectoryName = "data"
    fileprivate let kTrashDirectoryName = "trash"

    fileprivate var trashQueue: DispatchQueue
    fileprivate var path: URL
    fileprivate var dbPath: URL
    fileprivate var dataPath: URL
    fileprivate var trashPath: URL
    fileprivate var database: OpaquePointer?
    fileprivate var dbStmtCache: [String: Any]?
    fileprivate var dbLastOpenErrorTime: TimeInterval = 0
    fileprivate var dbOpenErrorCount: UInt = 0
    fileprivate(set) var type: KVStorageType
    fileprivate var errorLogsEnabled: Bool = true

    fileprivate let fileManger = FileManager.default

    init?(path: URL, type: KVStorageType) {
        guard !path.absoluteString.isEmpty, path.absoluteString.count <= kPathLengthMax else {
            print("KVStorage init error: invalid path: [\(path)].")
            return nil
        }

        self.path = path
        self.type = type
        trashQueue = OS_dispatch_queue_serial(label: "com.iteatime.cache.disk.trash")
        dataPath = path.appendingPathComponent(kDataDirectoryName)
        trashPath = path.appendingPathComponent(kTrashDirectoryName)
        dbPath = path.appendingPathComponent(kDBFileName)
        do {
            try fileManger.createDirectory(at: path, withIntermediateDirectories: true, attributes: nil)
            try fileManger.createDirectory(at: dataPath, withIntermediateDirectories: true, attributes: nil)
            try fileManger.createDirectory(at: trashPath, withIntermediateDirectories: true, attributes: nil)
        } catch {
            return nil
        }

        if !dbOpen() || !dbInitialize() {
            // db file may broken...
            dbClose()
            reset() // rebuild
            if !dbOpen() || !dbInitialize() {
                dbClose()
                log("KVStorage init error: fail to open sqlite db.")
                return nil
            }
        }
        fileEmptyTrashInBackground()
    }

    func sharedExtensionApplication() -> UIApplication? {
        return isAppExtension ? nil : UIApplication.shared
    }

    deinit {
        #if os(iOS) && canImport(UIKit)
        let taskID = sharedExtensionApplication()?.beginBackgroundTask(expirationHandler: nil)
        #endif
        dbClose()
        #if os(iOS) && canImport(UIKit)
        if let task = taskID {
            sharedExtensionApplication()?.endBackgroundTask(task)
        }
        #endif
    }

    // MARK: private
    fileprivate func reset() {
        do {
            try fileManger.removeItem(at: path.appendingPathComponent(kDBFileName))
            try fileManger.removeItem(at: path.appendingPathComponent(kDBShmFileName))
            try fileManger.removeItem(at: path.appendingPathComponent(kDBWalFileName))
            fileMoveAllToTrash()
            fileEmptyTrashInBackground()
        } catch {
            log("reset error: \(error)")
        }
    }

    fileprivate final func currentTime() -> TimeInterval {
        #if canImport(QuartzCore)
        return CACurrentMediaTime()
        #else
        return Date().timeIntervalSince1970
        #endif
    }

    fileprivate func log(_ items: Any..., separator: String = " ", terminator: String = "\n") {
        if errorLogsEnabled {
            print(items, separator, terminator)
        }
    }

    // MARK: File

    fileprivate func fileWrite(fileName: String, data: Data) -> Bool {
        do {
            try data.write(to: dataPath.appendingPathComponent(fileName))
        } catch {
            log("\(#function) line:(\(#line) file write error. fileName: (\(fileName)")
            return false
        }
        return true
    }

    fileprivate func fileRead(fileName: String) -> Data? {
        do {
            return try Data(contentsOf: dataPath.appendingPathComponent(fileName))
        } catch {
            log("\(#function) line:(\(#line) file read error. fileName: (\(fileName)")
            return nil
        }
    }

    @discardableResult
    fileprivate func fileDelete(fileName: String) -> Bool {
        do {
            try fileManger.removeItem(at: dataPath.appendingPathComponent(fileName))
        } catch {
            log("\(#function) line:(\(#line) file delete error. fileName: (\(fileName)")
            return false
        }
        return true
    }

    @discardableResult
    fileprivate func fileMoveAllToTrash() -> Bool {
        let uuid = UUID().uuidString
        let tmpPath = trashPath.appendingPathComponent(uuid)
        do {
            try fileManger.moveItem(at: dataPath, to: tmpPath)
            try fileManger.createDirectory(at: dataPath, withIntermediateDirectories: true, attributes: nil)
        } catch {
            log("\(#function) line:(\(#line) file move all to trash error.")
            return false
        }
        return true
    }

    // empty the trash if failed at last time
    fileprivate func fileEmptyTrashInBackground() {
        let trashPath = self.trashPath
        DispatchQueue.global().async {
            do {
                let directoryContents = try self.fileManger.contentsOfDirectory(atPath: trashPath.absoluteString)
                for path in directoryContents {
                    let fullPath = trashPath.appendingPathComponent(path)
                    try self.fileManger.removeItem(at: fullPath)
                }
            } catch {
                self.log("remove trash error: \(error)")
            }
        }
    }

    // MARK: DataBase

    fileprivate func dbOpen() -> Bool {
        guard database == nil else { return true }
        let result = sqlite3_open(dbPath.absoluteString, &database)
        guard result == SQLITE_OK else {
            database = nil
            dbStmtCache = nil
            dbLastOpenErrorTime = currentTime()
            dbOpenErrorCount+=1
            log("\(#function) line:\(#line) sqlite open failed (\(result)).")
            return false
        }
        dbStmtCache = Dictionary()
        dbLastOpenErrorTime = 0
        dbOpenErrorCount = 0
        return true
    }

    @discardableResult
    fileprivate func dbClose() -> Bool {
        guard let database = database else { return true }
        var retry = false
        var stmtFinalized = false
        dbStmtCache = nil
        repeat {
            retry = false
            let result = sqlite3_close(database)
            if result == SQLITE_BUSY || result == SQLITE_LOCKED {
                if !stmtFinalized {
                    stmtFinalized = true
                    var stmt = sqlite3_next_stmt(database, nil)
                    while stmt != nil {
                        sqlite3_finalize(stmt)
                        stmt = sqlite3_next_stmt(database, nil)
                        retry = true
                    }
                }
            } else if result != SQLITE_OK {
                log("\(#function) line:\(#line) sqlite close failed (\(result).")
            }
        } while(retry)
        self.database = nil
        return true
    }

    fileprivate func dbCheck() -> Bool {
        guard database == nil else { return true }
        if dbOpenErrorCount < kMaxErrorRetryCount &&
            currentTime() - dbLastOpenErrorTime > kMinRetryTimeInterval {
                return dbOpen() && dbInitialize()
        } else {
            return false
        }
    }

    fileprivate func dbInitialize() -> Bool {
        let sql = "pragma journal_mode = wal; pragma synchronous = normal;"
        + " create table if not exists manifest (key text, filename text, size integer, inline_data blob, modification_time integer, last_access_time integer, extended_data blob, primary key(key));"
            + " create index if not exists last_access_time_idx on manifest(last_access_time);"
        return dbExecute(sql)
    }

    fileprivate func dbCheckpoint() {
        guard dbCheck() else { return }
        // Cause a checkpoint to occur, merge `sqlite-wal` file to `sqlite` file.
        sqlite3_wal_checkpoint(database, nil)
    }

    fileprivate func dbExecute(_ sql: String) -> Bool {
        guard !sql.isEmpty, dbCheck() else { return false }
        return sqlite3_exec(database, sql, nil, nil, nil) == SQLITE_OK
    }

    fileprivate func dbPrepareStmt(_ sql: String) -> OpaquePointer? {
        guard dbCheck(), !sql.isEmpty, dbStmtCache != nil else { return nil }
        var stmt = dbStmtCache?[sql] as? OpaquePointer
        if stmt == nil {
            let result = sqlite3_prepare_v2(database, sql, -1, &stmt, nil)
            guard result == SQLITE_OK else {
                log("\(#function) line:\(#line) sqlite stmt prepare error (\(result)): \(errorMessage)")
                return nil
            }
            dbStmtCache?[sql] = stmt
        } else {
            sqlite3_reset(stmt)
        }
        return stmt
    }

    fileprivate var errorMessage: String {
        if let errorPointer = sqlite3_errmsg(database) {
            let errorMessage = String(cString: errorPointer)
            return errorMessage
        } else {
            return "No error message provided from sqlite."
        }
    }

    fileprivate func dbJoinedKeys(_ keys: [Any]) -> String {
        var string = ""
        let max = keys.count
        for index in 0 ..< max {
            string.append("?")
            if index + 1 != max {
                string.append(",")
            }
        }
        return string
    }

    fileprivate func dbBindJoinedKeys(keys: [String], stmt: OpaquePointer, fromIndex index: Int) {
        let max = keys.count
        for index in 0 ..< max {
            let key = keys[index] as NSString
            sqlite3_bind_text(stmt, Int32(index + index), key.utf8String, -1, nil)
        }
    }

    fileprivate func dbSave(key: String, value: Data, fileName: String?, extendedData: Data?) -> Bool {
        let sql = "insert or replace into manifest (key, filename, size, inline_data, modification_time, last_access_time, extended_data) values (?1, ?2, ?3, ?4, ?5, ?6, ?7);"
        guard let stmt = dbPrepareStmt(sql) else { return false }
        let timestamp = Int32(time(nil))
        sqlite3_bind_text(stmt, 1, (key as NSString).utf8String, -1, nil)
        if let file = fileName {
            sqlite3_bind_text(stmt, 2, (file as NSString).utf8String, -1, nil)
        } else {
            sqlite3_bind_text(stmt, 2, nil, -1, nil)
        }
        sqlite3_bind_int(stmt, 3, Int32(value.count))
        if fileName?.isEmpty ?? false {
            sqlite3_bind_blob(stmt, 4, (value as NSData).bytes, Int32(value.count), nil)
        } else {
            sqlite3_bind_blob(stmt, 4, nil, 0, nil)
        }
        sqlite3_bind_int(stmt, 5, timestamp)
        sqlite3_bind_int(stmt, 6, timestamp)
        if let exData = extendedData {
            sqlite3_bind_blob(stmt, 7, (exData as NSData).bytes, Int32(exData.count), nil)
        } else {
            sqlite3_bind_blob(stmt, 7, nil, 0, nil)
        }

        let result = sqlite3_step(stmt)
        if result != SQLITE_DONE {
            log("\(#function) line:(\(#line) sqlite insert error (\(result): (\(errorMessage))")
            return false
        }
        return true
    }

    @discardableResult
    fileprivate func dbUpdateAccessTime(_ key: String) -> Bool {
        let sql = "update manifest set last_access_time = ?1 where key = ?2;"
        guard let stmt = dbPrepareStmt(sql) else { return false }
        sqlite3_bind_int(stmt, 1, Int32(time(nil)))
        sqlite3_bind_text(stmt, 2, (key as NSString).utf8String, -1, nil)
        let result = sqlite3_step(stmt)
        if (result != SQLITE_DONE) {
            log("\(#function) line:(\(#line) sqlite update error (\(result): (\(errorMessage))")
            return false
        }
        return true
    }

    @discardableResult
    fileprivate func dbUpdateAccessTimes(_ keys: [String]) -> Bool {
        guard dbCheck() else { return false }
        let sql = "update manifest set last_access_time = \(Int32(time(nil))) where key in (\(dbJoinedKeys(keys)));"
        var stmtPointer: OpaquePointer?
        var result = sqlite3_prepare_v2(database, sql, -1, &stmtPointer, nil)
        guard result == SQLITE_OK, let stmt = stmtPointer else {
            log("\(#function) line:(\(#line) sqlite stmt prepare error (\(result): (\(errorMessage))")
            return false
        }
        dbBindJoinedKeys(keys: keys, stmt: stmt, fromIndex: 1)
        result = sqlite3_step(stmt)
        sqlite3_finalize(stmt)
        if (result != SQLITE_DONE) {
            log("\(#function) line:(\(#line) sqlite update error (\(result): (\(errorMessage))")
            return false
        }
        return true
    }

    @discardableResult
    fileprivate func dbDeleteItem(_ key: String) -> Bool {
        let sql = "delete from manifest where key = ?1;"
        guard let stmt = dbPrepareStmt(sql) else { return false }
        sqlite3_bind_text(stmt, 1, (key as NSString).utf8String, -1, nil)
        let result = sqlite3_step(stmt)
        if (result != SQLITE_DONE) {
            log("\(#function) line:(\(#line) sqlite delete error (\(result): (\(errorMessage))")
            return false
        }
        return true
    }

    fileprivate func dbDeleteItems(_ keys: [String]) -> Bool {
        guard dbCheck() else { return false }
        let sql = "delete from manifest where key in (\(dbJoinedKeys(keys));"
        var stmtPointer: OpaquePointer?
        var result = sqlite3_prepare_v2(database, sql, -1, &stmtPointer, nil)
        guard result == SQLITE_OK, let stmt = stmtPointer else {
            log("\(#function) line:(\(#line) sqlite stmt prepare error (\(result): (\(errorMessage))")
            return false
        }
        dbBindJoinedKeys(keys: keys, stmt: stmt, fromIndex: 1)
        result = sqlite3_step(stmt)
        sqlite3_finalize(stmt)
        if (result == SQLITE_ERROR) {
            log("\(#function) line:(\(#line) sqlite delete error (\(result): (\(errorMessage))")
            return false
        }
        return true
    }

    fileprivate func dbDeleteItem(sql: String, param: Int32) -> Bool {
        guard let stmt = dbPrepareStmt(sql) else { return false }
        sqlite3_bind_int(stmt, 1, param)
        let result = sqlite3_step(stmt)
        if (result != SQLITE_DONE) {
            log("\(#function) line:(\(#line) sqlite delete error (\(result): (\(errorMessage))")
            return false
        }
        return true
    }

    fileprivate func dbDeleteItemsWithSizeLargerThan(_ size: Int) -> Bool {
        return dbDeleteItem(sql: "delete from manifest where size > ?1;", param: Int32(size))
    }

    fileprivate func dbDeleteItemsWithTimeEarlierThan(_ time: Int) -> Bool {
        return dbDeleteItem(sql: "delete from manifest where last_access_time < ?1;", param: Int32(time))
    }

    fileprivate func dbGetItemFromStmt(stmt: OpaquePointer, excludeInlineData: Bool) -> KVStorageItem {
        let item = KVStorageItem()
        var index: Int32 = 0
        item.key = String(cString: UnsafePointer(sqlite3_column_text(stmt, index)))
        index += 1
        item.fileName = String(cString: UnsafePointer(sqlite3_column_text(stmt, index)))
        index += 1
        item.size = Int(sqlite3_column_int(stmt, index))
        index += 1
        let inlineData: UnsafeRawPointer? = excludeInlineData ? nil : sqlite3_column_blob(stmt, index)
        let inlineDataLength = excludeInlineData ? 0 : sqlite3_column_bytes(stmt, index)
        index += 1
        if inlineDataLength > 0 && (inlineData != nil) {
            item.value = NSData(bytes: inlineData, length: Int(inlineDataLength)) as Data
        }
        item.modTime = Int(sqlite3_column_int(stmt, index))
        index += 1
        item.accessTime = Int(sqlite3_column_int(stmt, index))
        index += 1
        let extendedData: UnsafeRawPointer? = sqlite3_column_blob(stmt, index)
        let extendedDataLength = sqlite3_column_bytes(stmt, index)
        if extendedDataLength > 0 && (extendedData != nil) {
            item.extendedData = NSData(bytes: extendedData, length: Int(extendedDataLength)) as Data
        }
        return item
    }

    fileprivate func dbGetItem(key: String, excludeInlineData: Bool) -> KVStorageItem? {
        let sql = excludeInlineData ? "select key, filename, size, modification_time, last_access_time, extended_data from manifest where key = ?1;"
            : "select key, filename, size, inline_data, modification_time, last_access_time, extended_data from manifest where key = ?1;"
        guard let stmt = dbPrepareStmt(sql) else { return nil }
        sqlite3_bind_text(stmt, 1, (key as NSString).utf8String, -1, nil)
        var item: KVStorageItem?
        let result = sqlite3_step(stmt)
        if (result == SQLITE_ROW) {
            item = dbGetItemFromStmt(stmt: stmt, excludeInlineData: excludeInlineData)
        } else {
            if (result != SQLITE_DONE) {
                log("\(#function) line:(\(#line) sqlite query error (\(result): (\(errorMessage))")
            }
        }
        return item
    }

    fileprivate func dbGetItems(keys: [String], excludeInlineData: Bool) -> [KVStorageItem]? {
        guard dbCheck() else { return nil }
        let sql: String
        if (excludeInlineData) {
            sql = "select key, filename, size, modification_time, last_access_time, extended_data from manifest where key in (\(dbJoinedKeys(keys)));"
        } else {
            sql = "select key, filename, size, inline_data, modification_time, last_access_time, extended_data from manifest where key in (\(dbJoinedKeys(keys))"
        }
        var stmtPointer: OpaquePointer?
        var result = sqlite3_prepare_v2(database, sql, -1, &stmtPointer, nil)
        guard result == SQLITE_OK, let stmt = stmtPointer else {
            log("\(#function) line:(\(#line) sqlite stmt prepare error (\(result): (\(errorMessage))")
            return nil
        }
        dbBindJoinedKeys(keys: keys, stmt: stmt, fromIndex: 1)
        var items: [KVStorageItem]? = [KVStorageItem]()
        repeat {
            result = sqlite3_step(stmt)
            if (result == SQLITE_ROW) {
                items?.append(dbGetItemFromStmt(stmt: stmt, excludeInlineData: excludeInlineData))
            } else if (result == SQLITE_DONE) {
                break
            } else {
                log("\(#function) line:(\(#line) sqlite query error (\(result): (\(errorMessage))")
                items = nil
                break
            }
        } while(true)
        sqlite3_finalize(stmt)
        return items
    }

    fileprivate func dbGetValue(key: String) -> Data? {
        let sql = "select inline_data from manifest where key = ?1;"
        guard let stmt = dbPrepareStmt(sql) else { return nil }
        sqlite3_bind_text(stmt, 1, (key as NSString).utf8String, -1, nil)
        let result = sqlite3_step(stmt)
        if (result == SQLITE_ROW) {
            let inlineData: UnsafeRawPointer? = sqlite3_column_blob(stmt, 0)
            let inlineDataLength = sqlite3_column_bytes(stmt, 0)
            guard inlineDataLength > 0 && (inlineData != nil) else {
                return nil
            }
            return NSData(bytes: inlineData, length: Int(inlineDataLength)) as Data
        } else {
            if (result != SQLITE_DONE) {
                log("\(#function) line:(\(#line) sqlite query error (\(result): (\(errorMessage))")
            }
            return nil
        }
    }

    fileprivate func dbGetFilename(key: String) -> String? {
        let sql = "select filename from manifest where key = ?1;"
        guard let stmt = dbPrepareStmt(sql) else { return nil }
        sqlite3_bind_text(stmt, 1, (key as NSString).utf8String, -1, nil)
        let result = sqlite3_step(stmt)
        if (result == SQLITE_ROW) {
            return String(cString: UnsafePointer(sqlite3_column_text(stmt, 0)))
        } else {
            if (result != SQLITE_DONE) {
                log("\(#function) line:(\(#line) sqlite query error (\(result): (\(errorMessage))")
            }
            return nil
        }
    }

    fileprivate func dbGetFileNames(keys: [String]) -> [String]? {
        guard dbCheck() else { return nil }
        let sql = "select filename from manifest where key in (\(dbJoinedKeys(keys)));"
        var stmtPointer: OpaquePointer?
        var result = sqlite3_prepare_v2(database, sql, -1, &stmtPointer, nil)
        guard result == SQLITE_OK, let stmt = stmtPointer else {
            log("\(#function) line:(\(#line) sqlite stmt prepare error (\(result): (\(errorMessage))")
            return nil
        }
        dbBindJoinedKeys(keys: keys, stmt: stmt, fromIndex: 1)
        var fileNames: [String]? = [String]()
        repeat {
            result = sqlite3_step(stmt)
            if (result == SQLITE_ROW) {
                fileNames?.append(String(cString: UnsafePointer(sqlite3_column_text(stmt, 0))))
            } else if (result == SQLITE_DONE) {
                break
            } else {
                log("\(#function) line:(\(#line) sqlite query error (\(result): (\(errorMessage))")
                fileNames = nil
                break
            }
        } while(true)
        sqlite3_finalize(stmt)
        return fileNames
    }

    fileprivate func dbGetFilenames(sql: String, param: Int32) -> [String]? {
        guard let stmt = dbPrepareStmt(sql) else { return nil }
        sqlite3_bind_int(stmt, 1, Int32(param))
        var fileNames: [String]? = [String]()
        repeat {
            let result = sqlite3_step(stmt)
            if (result == SQLITE_ROW) {
                fileNames?.append(String(cString: UnsafePointer(sqlite3_column_text(stmt, 0))))
            } else if (result == SQLITE_DONE) {
                break
            } else {
                log("\(#function) line:(\(#line) sqlite query error (\(result): (\(errorMessage))")
                fileNames = nil
                break
            }
        } while(true)
        sqlite3_finalize(stmt)
        return fileNames
    }

    fileprivate func dbGetFilenamesWithSizeLargerThan(_ size: Int) -> [String]? {
        let sql = "select filename from manifest where size > ?1 and filename is not null;"
        return dbGetFilenames(sql: sql, param: Int32(size))
    }

    fileprivate func dbGetFilenamesWithTimeEarlierThan(_ time: Int) -> [String]? {
        let sql = "select filename from manifest where last_access_time < ?1 and filename is not null;"
        return dbGetFilenames(sql: sql, param: Int32(time))
    }

    fileprivate func dbGetItemSizeInfoOrderByTimeAscWithLimit(count: Int) -> [KVStorageItem]? {
        let sql = "select key, filename, size from manifest order by last_access_time asc limit ?1;"
        guard let stmt = dbPrepareStmt(sql) else { return nil }
        var items: [KVStorageItem]? = [KVStorageItem]()
        repeat {
            let result = sqlite3_step(stmt)
            if (result == SQLITE_ROW) {
                let item = KVStorageItem()
                item.key = String(cString: UnsafePointer(sqlite3_column_text(stmt, 0)))
                item.fileName = String(cString: UnsafePointer(sqlite3_column_text(stmt, 1)))
                item.size = Int(sqlite3_column_int(stmt, 2))
                items?.append(item)
            } else if (result == SQLITE_DONE) {
                break
            } else {
                log("\(#function) line:(\(#line) sqlite query error (\(result): (\(errorMessage))")
                items = nil
                break
            }
        } while(true)
        sqlite3_finalize(stmt)
        return items
    }

    fileprivate func dbGetItemCount(key: String) -> Int {
        let sql = "select count(key) from manifest where key = ?1;"
        guard let stmt = dbPrepareStmt(sql) else { return -1 }
        sqlite3_bind_text(stmt, 1, (key as NSString).utf8String, -1, nil)
        let result = sqlite3_step(stmt)
        if result != SQLITE_ROW {
            log("\(#function) line:(\(#line) sqlite query error (\(result): (\(errorMessage))")
            return -1
        }
        return Int(sqlite3_column_int(stmt, 0))
    }

    fileprivate func dbGetInt(_ sql: String) -> Int {
        guard let stmt = dbPrepareStmt(sql) else { return -1 }
        let result = sqlite3_step(stmt)
        if result != SQLITE_ROW {
            log("\(#function) line:(\(#line) sqlite query error (\(result): (\(errorMessage))")
            return -1
        }
        return Int(sqlite3_column_int(stmt, 0))
    }

    fileprivate func dbGetTotalItemSize() -> Int {
        return dbGetInt("select sum(size) from manifest;")
    }

    fileprivate func dbGetTotalItemCount() -> Int {
        return dbGetInt("select count(*) from manifest;")
    }

    // MARK: Public
    public func saveItem(key: String, value: Data, fileName: String?, extendedData: Data?) -> Bool {
        guard !key.isEmpty, !value.isEmpty else { return false }
        if type == .file && fileName?.isEmpty ?? true { return false }
        if let file = fileName, !file.isEmpty {
            if !fileWrite(fileName: file, data: value) {
                return false
            }
            if !dbSave(key: key, value: value, fileName: file, extendedData: extendedData) {
                fileDelete(fileName: file)
                return false
            }
            return true
        } else {
            if type != .sqlite {
                if let file = dbGetFilename(key: key) {
                    fileDelete(fileName: file)
                }
            }
            return dbSave(key: key, value: value, fileName: nil, extendedData: extendedData)
        }
    }

    public func removeItem(key: String) -> Bool {
        guard !key.isEmpty else { return false }
        switch type {
        case .sqlite:
            return dbDeleteItem(key)
        case .file, .mixed:
            if let fileName = dbGetFilename(key: key) {
                fileDelete(fileName: fileName)
            }
            return dbDeleteItem(key)
        }
    }

    public func removeItems(keys: [String]) -> Bool {
        guard !keys.isEmpty else { return false }
        switch type {
        case .sqlite:
            return dbDeleteItems(keys)
        case .file, .mixed:
            if let fileNames = dbGetFileNames(keys: keys), !fileNames.isEmpty {
                for file in fileNames {
                    fileDelete(fileName: file)
                }
            }
            return dbDeleteItems(keys)
        }
    }

    public func removeAllItems() -> Bool {
        guard dbClose() else { return false }
        reset()
        guard dbOpen() else { return false }
        guard dbInitialize() else { return false }
        return true
    }

    public func removeItemsLargerThanSize(_ size: Int) -> Bool {
        guard size != Int.max else { return true }
        guard size > 0 else { return removeAllItems() }
        switch type {
        case .sqlite:
            if dbDeleteItemsWithSizeLargerThan(size) {
                dbCheckpoint()
                return true
            }
        case .file, .mixed:
            if let fileNames = dbGetFilenamesWithSizeLargerThan(size) {
                for file in fileNames {
                    fileDelete(fileName: file)
                }
            }
            if dbDeleteItemsWithSizeLargerThan(size) {
                dbCheckpoint()
                return true
            }
        }
        return false
    }

    public func removeItemsEarlierThanTime(_ time: Int) -> Bool {
        guard time > 0 else { return true }
        guard time != Int.max else { return removeAllItems() }
        switch type {
        case .sqlite:
            if dbDeleteItemsWithTimeEarlierThan(time) {
                dbCheckpoint()
                return true
            }
        case .file, .mixed:
            if let fileNames = dbGetFilenamesWithTimeEarlierThan(time) {
                for file in fileNames {
                    fileDelete(fileName: file)
                }
            }
            if dbDeleteItemsWithTimeEarlierThan(time) {
                dbCheckpoint()
                return true
            }
        }
        return false
    }

    public func removeItemsToFitSize(_ maxSize: Int) -> Bool {
        guard maxSize != Int.max else { return true }
        guard maxSize > 0 else { return removeAllItems() }
        var total = dbGetTotalItemSize()
        guard total >= 0 else { return false }
        guard total > maxSize else { return true }
        var suc = false
        dbGetItemSizeInfoOrderByTimeAscWithLimit(count: 16)?.forEach({ (item) in
            if let fileName = item.fileName {
                fileDelete(fileName: fileName)
            }
            if let key = item.key {
                suc = dbDeleteItem(key)
            } else {
                suc = true
            }
            total -= item.size
            if total <= maxSize || !suc {
                return
            }
        })
        if suc {
            dbCheckpoint()
        }
        return suc
    }

    public func removeItemsToFitCount(_ maxCount: Int) -> Bool {
        guard maxCount != Int.max else { return true }
        guard maxCount > 0 else { return removeAllItems() }
        var total = dbGetTotalItemCount()
        guard total >= 0 else { return false }
        guard total > maxCount else { return true }
        var suc = false
        dbGetItemSizeInfoOrderByTimeAscWithLimit(count: 16)?.forEach({ (item) in
            if let fileName = item.fileName {
                fileDelete(fileName: fileName)
            }
            if let key = item.key {
                suc = dbDeleteItem(key)
            } else {
                suc = true
            }
            total -= 1
            if total <= maxCount || !suc {
                return
            }
        })
        if suc {
            dbCheckpoint()
        }
        return suc
    }

    public func removeAllItemsWithProgressBlock(progress: ((_ removedCount: Int, _ totalCount: Int) -> Void)?,
                                                end: ((_ error: Bool) -> Void)?) {
        let total = dbGetTotalItemCount()
        if total <= 0 {
            end?(total < 0)
        } else {
            var left = total
            var suc = false
            dbGetItemSizeInfoOrderByTimeAscWithLimit(count: 32)?.forEach({ (item) in
                if let fileName = item.fileName {
                    fileDelete(fileName: fileName)
                }
                if let key = item.key {
                    suc = dbDeleteItem(key)
                } else {
                    suc = true
                }
                left -= 1
                if left <= 0 || !suc {
                    return
                }
                progress?(total - left, total)
            })
            if suc {
                dbCheckpoint()
            }
            end?(!suc)
        }
    }

    public func getItemForKey(_ key: String) -> KVStorageItem? {
        guard !key.isEmpty else { return nil }
        guard let item = dbGetItem(key: key, excludeInlineData: false) else { return nil }
        dbUpdateAccessTime(key)
        if let fileName = item.fileName {
            if let value = fileRead(fileName: fileName) {
                item.value = value
            } else {
                dbDeleteItem(key)
                return nil
            }
        }
        return item
    }

    public func getItemInfoForKey(_ key: String) -> KVStorageItem? {
        guard !key.isEmpty else { return nil }
        return dbGetItem(key: key, excludeInlineData: true)
    }

    public func getItemValueForKey(_ key: String) -> Data? {
        guard !key.isEmpty else { return nil }
        var value: Data?
        switch type {
        case .file:
            if let fileName = dbGetFilename(key: key) {
                value = fileRead(fileName: fileName)
                if value == nil {
                    dbDeleteItem(key)
                }
            }
        case .sqlite:
            value = dbGetValue(key: key)
        case .mixed:
            if let fileName = dbGetFilename(key: key) {
                value = fileRead(fileName: fileName)
                if value == nil {
                    dbDeleteItem(key)
                }
            } else {
                value = dbGetValue(key: key)
            }
        }
        if value != nil {
            dbUpdateAccessTime(key)
        }
        return value
    }

    public func getItemForKeys(_ keys: [String]) -> [KVStorageItem]? {
        guard !keys.isEmpty else { return nil }
        if var items = dbGetItems(keys: keys, excludeInlineData: false), !items.isEmpty {
            if type == .sqlite {
                var index = 0
                var max = items.count
                repeat {
                    let item = items[index]
                    if let fileName = item.fileName {
                        if let value = fileRead(fileName: fileName) {
                            item.value = value
                        } else {
                            if let key = item.key {
                                dbDeleteItem(key)
                            }
                            items.remove(at: index)
                            index -= 1
                            max -= 1
                        }
                    }
                    index += 1
                } while(index < max)
            }
            return items.isEmpty ? nil : items
        } else {
            return nil
        }
    }

    public func getItemInfoForKeys(_ keys: [String]) -> [KVStorageItem]? {
        guard !keys.isEmpty else { return nil }
        return dbGetItems(keys: keys, excludeInlineData: true)
    }

    public func getItemValueForKeys(_ keys: [String]) -> [String: Any]? {
        guard let items = getItemForKeys(keys) else { return nil }
        var keyAndValue = [String: Any]()
        for item in items {
            if let key = item.key, let value = item.value {
                keyAndValue[key] = value
            }
        }
        return keyAndValue.isEmpty ? nil : keyAndValue
    }

    public func itemExistsForKey(_ key: String) -> Bool {
        guard !key.isEmpty else { return false }
        return dbGetItemCount(key: key) > 0
    }

    public func getItemsCount() -> Int {
        return dbGetTotalItemCount()
    }

    public func getItemsSize() -> Int {
        return dbGetTotalItemSize()
    }
}
