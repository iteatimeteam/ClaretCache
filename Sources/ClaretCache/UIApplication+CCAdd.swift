//
//  UIApplication+CCAdd.swift
//  ClaretCacheDemo
//
//  Created by HZheng on 2019/7/28.
//  Copyright © 2019 com.ClaretCache. All rights reserved.
//

import UIKit.UIApplication

var IsAppExtension: Bool {
    guard Bundle.main.bundleURL.pathExtension != "appex" else {
        return false
    }
    guard let app = NSClassFromString("UIApplication"), app.value(forKey: "shared") != nil else {
        return true
    }
    return false
}

extension UIApplication {
    static func isAppExtension() -> Bool {
        return IsAppExtension;
    }
    
    static func sharedExtensionApplication() -> UIApplication? {
        return IsAppExtension ? nil : UIApplication.shared
    }
}
