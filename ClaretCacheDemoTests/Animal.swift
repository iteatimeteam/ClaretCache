//
//  Animal.swift
//  ClaretCacheDemoTests
//
//  Created by HZheng on 2019/8/4.
//  Copyright © 2019 com.ClaretCache. All rights reserved.
//

import UIKit

class Animal : NSObject, NSSecureCoding {
    static var supportsSecureCoding: Bool = true
    var name: String
    var age: Int
//    var image: UIImage?

    func encode(with aCoder: NSCoder) {
        aCoder.encode(name, forKey: "name")
        aCoder.encode(age, forKey: "age")
//        if let img = image {
//            aCoder.encode(img.pngData(), forKey: "image")
//        }
    }

    required init?(coder aDecoder: NSCoder) {
        age = aDecoder.decodeInteger(forKey: "age")
        name = aDecoder.decodeObject(forKey: "name") as! String
//        if let data = aDecoder.decodeObject(forKey: "image") as? Data {
//            image = UIImage.init(data: data)
//        }
    }

    init(name: String, age: Int) {
        self.name = name
        self.age = age
//        image = UIImage.init(named: "banner")
    }

    func isEqual(_ object: Animal?) -> Bool {
        guard object != nil else {
            return false
        }
        return name == object?.name && age == object?.age
    }
}
