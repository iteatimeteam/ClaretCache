# ClaretCache Swift代码选型规范

## 目标

本规约旨在: 

* 使代码易读，易理解, 易维护.
* 减少编写代码时的认知负担.
* 使项目成员能更专注讨论代码逻辑而不是代码写法.


## 指导原则

* 本规约是 [Swift API Design Guidelines](https://swift.org/documentation/api-design-guidelines/) 的扩展，规约内容不应该和官方文档相抵触.
* 如果规约修改了代码格式, 则需要重新自动格式化(使用SwiftLint)


## 目录

1. [Xcode 配置](#xcode-配置)
1. [命名](#命名)
1. [风格](#风格)
    1. [函数](#函数)
    1. [闭包](#)
    1. [操作符](#操作符)
1. [最佳实践](#最佳实践)
1. [与Objc的交互](#与Objc的交互)

## Xcode 配置

*  **每行的最大列宽应为100个字符.** (考虑到外接大屏显示器, 我们选择最大列宽超过80个字符)

*  **每行使用2个空格缩进.**

*  **删除所有行尾的空白字符.**

**[⬆ 返回顶部](#目录)**

## 命名

* **对于类型(值类型或引用类型)和协议, 使用大写驼峰命名法; 其余则使用小写驼峰命名法.** 

  <details>
  <summary>示例</summary>

  ```swift
  protocol Person {
    // ...
  }

  class Teacher: Person {

    enum Gender {
      // ...
    }

    class Course {
      // ...
    }

    var courses: [Course] = []
    static let schoolName: String = "Stanford"

    func addCourse(_ course: Course) {
      // ...
    }
  }

  let teacher = Teacher()
  ```

  </details>

  _特例: 给自定义私有属性添加下划线前缀. 当自定义的属性和系统属性冲突时, 并且需要赋予自定义属性更高的权限时.

  <details>
  <summary>示例</summary>
  
  ```swift
  class DemoViewController: UIViewController {
    private lazy var _view = CustomView()

    loadView() {
      self.view = _view
    }
  }
  ```

  </details>

*  **给布尔值命名时请参考 `isTeacher`, `hasCourse`这样的命名方式.** 该方式能更好地体现其是一个布尔类型, 而非其他类型.

* **名称中的缩略语(例如URL)，除非该缩略语是名称的开头，否则一律使用大写.** *(名称: 变量名，函数名)*

  <details>
  <summary>示例</summary>

  ```swift
  //错误示范
  class UrlValidator {

    func isValidUrl(_ URL: URL) -> Bool {
      // ...
    }

    func isUrlReachable(_ URL: URL) -> Bool {
      // ...
    }
  }

  let URLValidator = UrlValidator().isValidUrl(/* some URL */)

  // 正确示范
  class URLValidator {

    func isValidURL(_ url: URL) -> Bool {
      // ...
    }

    func isURLReachable(_ url: URL) -> Bool {
      // ...
    }
  }

  let urlValidator = URLValidator().isValidURL(/* some URL */)
  ```

  </details>

* **名称应该明确体现其功能. 从左至右顺序应为: 常见部分到具体部分.** 常见部分是指: 最能帮助我们锁定目标的类型名词, 一般粒度较大; 具体部分是指: 粒度最小的部分。

  <details>
  <summary>示例</summary>

  ```swift
  // 错误示范
  let rightTitleMargin: CGFloat
  let leftTitleMargin: CGFloat
  let bodyRightMargin: CGFloat
  let bodyLeftMargin: CGFloat

  // 正确示范
  let titleMarginRight: CGFloat
  let titleMarginLeft: CGFloat
  let bodyMarginRight: CGFloat
  let bodyMarginLeft: CGFloat
  ```

  </details>

* **如果名称不明确，请在名称中包含有关类型的提示.**

  <details>
  <summary>示例</summary>

  ```swift
  // 错误示范
  let title: String
  let cancel: UIButton

  // 正确示范
  let titleText: String
  let cancelButton: UIButton
  ```

  </details>

* **事件处理函数命名使用过去时.**

  <details>
  <summary>示例</summary>

  ```swift
  // 错误示例
  class ExperiencesViewController {

    private func handleBookButtonTap() {
      // ...
    }

    private func modelChanged() {
      // ...
    }
  }

  // 正确示例
  class ExperiencesViewController {

    private func didTapBookButton() {
      // ...
    }

    private func modelDidChange() {
      // ...
    }
  }
  ```

  </details>

* **避免Objective-C的命名前缀.**

  <details>
  <summary>示例</summary>

  ```swift
  // 错误示例
  class AIRAccount {
    // ...
  }

  // 正确示例
  class Account {
    // ...
  }
  ```

  </details>

**[⬆ 返回顶部](#目录)**

## 风格

* **当编译器可推断变量类型时, 不需要显式为变量添加类型**

  <details>
  <summary>示例</summary>

  ```swift
  // 错误示例
  let teacher: Teacher = Teacher()

  // 正确示例
  let teacher = Teacher()
  ```

  ```swift
  enum Weather {
    case sunny
    case cloudy
  }

  func someWeather() -> Weather {
    // WRONG
    return Weather.sunny

    // RIGHT
    return .sunny
  }
  ```

  </details>

* **不要使用 `self` 关键字，除非产生二义性.**

  <details>
  <summary>示例</summary>
  
  ```swift
  final class Listing {

    init(capacity: Int, allowsPets: Bool) {
      // 错误示例
      self.capacity = capacity
      self.isFamilyFriendly = !allowsPets // `self.` not required here

      // 正确示例
      self.capacity = capacity
      isFamilyFriendly = !allowsPets
    }
  }
  ```

  </details>

* **当元组作为返回值时, 给每一个成员添加名称，使其含义更为清晰.** 如果元祖包含超过3个成员的话, 则建议使用结构体.

  <details>
  <summary>示例</summary>

  ```swift
  // 错误示例
  func numbers() -> (Int, Int) {
    return (6, 6)
  }
  let numbers = numbers()
  print(numbers.0)

  // 正确示例
  func numbers() -> (x: Int, y: Int) {
    return (x: 6, y: 6)
  }

  // 替代方案
  func numbers2() -> (x: Int, y: Int) {
    let x = is 6
    let y = 6
    return (x, y)
  }

  let numbers = numbers()
  numbers
  numbers
  ```

  </details>

* **当声明类型或者变量时, 变量名后紧跟冒号，之后添加空格符, 空格符后紧跟类型.**

  <details>
  <summary>示例</summary>

  ```swift
  
  // 错误示例
  var something : Double = 0

  // 正确示例
  var something: Double = 0
  ```

  ```swift
  // 错误示例
  class MyClass : SuperClass {
    // ...
  }

  // 正确示例
  class MyClass: SuperClass {
    // ...
  }
  ```

  ```swift
  // 错误示例
  var dict = [KeyType:ValueType]()
  var dict = [KeyType : ValueType]()

  // 正确示例
  var dict = [KeyType: ValueType]()
  ```

  </details>

* **返回箭头两侧添加空格以增加可读性.**

  <details>
  <summary>示例</summary>

  ```swift
  // 错误示例
  func doSomething()->String {
    // ...
  }

  // 正确示例
  func doSomething() -> String {
    // ...
  }
  ```

  </details>

* **去除不必要的括号.**

  <details>
  <summary>示例</summary>
  
  ```swift
  // 错误示例
  if (userCount > 0) { ... }
  switch (someValue) { ... }
  let evens = userCounts.filter { (number) in number % 2 == 0 }
  let squares = userCounts.map() { $0 * $0 }

  // 正确示例
  if userCount > 0 { ... }
  switch someValue { ... }
  let evens = userCounts.filter { number in number % 2 == 0 }
  let squares = userCounts.map { $0 * $0 }
  ```
  
  ```swift
  // 错误示例
	if case .done(_) = result { ... }

	switch animal {
	case .dog(_, _, _):
  		...
	}

	// 正确示例
	if case .done = result { ... }

	switch animal {
	case .dog:
  		...
	}
  ```

  </details>

* **当使用`switch`时，默认情况使用 @unknown 来修饰 `default`关键字.**

  <details>
  <summary>示例</summary>

  ```swift
  // 错误示例
  let someFruit = .apple
	switch someFruit {
		case "apple":
    		print("apple")
		default:
    		print("Some other fruits.")
	}

  // 正确示例
  switch someFruit {
	case .apple:
    	... 
	@unknown default:
    	print("We don't sell that kind of fruit here.")
   }
  ```

  </details>

### 函数

* **函数体积不应超过百行; 并且需要对函数入参进行判断; 其内部应尽量避免使用全局变量来传递数据.**

  <details>
  <summary>示例</summary>
 
 	```swift
 	// 正确示例
 	func saveRSS(rss: RSS?, store: Store?) {
 	 guard let rss = rss else { return }
 	 
 	 guard let store = store else { return }
 	 
 	 return
   }
   ```
   </details>

* **当函数没有返回值时, 不需指定 `Void` 关键字.**

  <details>
  <summary>示例</summary>
  
  ```swift
  // 错误示例
  func doSomething() -> Void {
    ...
  }

  // 正确示例
  func doSomething() {
    ...
  }
  ```

  </details>

### 闭包

* **使用 `Void` 作为闭包返回值类型(当返回为空时).**
  <details>
  <summary>示例</summary>

  ```swift
  // 错误示例
  func doSomething(completion: () -> ()) {
    ...
  }

  // 正确示例
  func doSomething(completion: () -> Void) {
    ...
  }
  ```

  </details>

* **使用 (`_`) 代替闭包中未被使用的参数.**

    <details>
    <summary>示例</summary>

    ```swift
    // 错误示例
    someAsyncThing() { argument1, argument2, argument3 in
      print(argument3)
    }

    // 正确示例
    someAsyncThing() { _, _, argument3 in
      print(argument3)
    }
    ```

    </details>

### 操作符

* **二元操作符两侧应添加空格.** 该规则不适用于以下操作符 (e.g. `1...6` 或者 `1..<6`)
  <details>

  ```swift
  <summary>示例</summary>
  
  // 错误示例
  let capacity = 1+2
  let capacity = currentCapacity   ?? 0
  let mask = (UIAccessibilityTraitButton|UIAccessibilityTraitSelected)
  let capacity=newCapacity
  let latitude = region.center.latitude - region.span.latitudeDelta/2.0

  // 正确示例
  let capacity = 1 + 2
  let capacity = currentCapacity ?? 0
  let mask = (UIAccessibilityTraitButton | UIAccessibilityTraitSelected)
  let capacity = newCapacity
  let latitude = region.center.latitude - (region.span.latitudeDelta / 2.0)
  ```

  </details>

**[⬆ 返回顶部](#目录)**

## 最佳实践

* **尽可能在初始化函数 `init` 中完成对变量的初始化工作; 避免直接声明强制解包的变量.** 但是UIViewController的 `view `变量不在此考虑范围内.

  <details>
  <summary>示例</summary>
  
  ```swift
  // 错误示例
  class MyClass: NSObject {

    init() {
      super.init()
      someValue = 5
    }

    var someValue: Int!
  }

  // 正确示例
  class MyClass: NSObject {

    init() {
      someValue = 0
      super.init()
    }

    var someValue: Int
  }
  ```

  </details>

* **避免在 `init()` 中声明一切耗时或产生副作用的操作.** 例如建立数据库连接，读取数据等等.

* **将属性观察器中的复杂逻辑提取到函数中.**

  <details>
  <summary>示例</summary>
  
  ```swift
  // 错误示例
  class TextField {
    var text: String? {
      didSet {
        guard oldValue != text else {
          return
        }

        // Do a bunch of text-related side-effects.
      }
    }
  }

  // 正确示例
  class TextField {
    var text: String? {
      didSet { textDidUpdate(from: oldValue) }
    }

    private func textDidUpdate(from oldValue: String?) {
      guard oldValue != text else {
        return
      }

      // Do a bunch of text-related side-effects.
    }
  }
  ```

  </details>

* **将复杂的回调逻辑代码放入函数**. 这样可以有效减少嵌套和 `weak self` 的使用。如果需要使用 `self` 关键字，则使用 `guard` 将其解包后使用. 

  <details>
  <summary>示例</summary>

  ```swift
  //错误示例
  class MyClass {

    func request(completion: () -> Void) {
      API.request() { [weak self] response in
        if let strongSelf = self {
          // Processing and side effects
        }
        completion()
      }
    }
  }

  // 正确示例
  class MyClass {

    func request(completion: () -> Void) {
      API.request() { [weak self] response in
        guard let strongSelf = self else { return }
        strongSelf.doSomething(strongSelf.property)
        completion()
      }
    }

    func doSomething(nonOptionalParameter: SomeClass) {
      // Processing and side effects
    }
  }
  ```

  </details>

* **在一个范围 `Scope` 起始部分使用guard来做逻辑或者是参数检查.**

* **访问控制符需要有清晰地设定.** 首选 `public, open, private` 而不是 `fileprivate`.

* **访避免使用全局函数.**

  <details>
  <summary>示例</summary>

  ```swift
  // 错误示例
  func age(of person, bornAt timeInterval) -> Int {
    // ...
  }

  func jump(person: Person) {
    // ...
  }

  // 正确示例
  class Person {
    var bornAt: TimeInterval

    var age: Int {
      // ...
    }

    func jump() {
      // ...
    }
  }
  ```

  </details>

* **将私有常量放于文件顶部.** 若常量是外部或模块内可见，则将其定义为静态属性.

  <details>
  <summary>示例</summary>

  ```swift
  // 标准示例
  private let privateValue = "secret"

  public class MyClass {

    public static let publicValue = "something"

    func doSomething() {
      print(privateValue)
      print(MyClass.publicValue)
    }
  }
  ```

  </details>

* **使用无具体 `case` 的枚举类型来管理 `public, internal`的常量和函数.** 这样做可有效避免命名空间产生的冲突.

  <details>
  <summary>示例</summary>

  ```swift
  // 标准示例
  enum Environment {

    enum Earth {
      static let gravity = 9.8
    }

    enum Moon {
      static let gravity = 1.6
    }
  }
  ```

  </details>

* **使用Swift枚举自产生值，除非特定业务需要映射到外部资源.**

  <details>
  <summary>示例</summary>

  ```swift
  // 错误示例
  enum ErrorType: String {
    case error = "error"
    case warning = "warning"
  }

  enum UserType: String {
    case owner
    case manager
    case member
  }

  enum Planet: Int {
    case mercury = 0
    case venus = 1
    case earth = 2
    case mars = 3
    case jupiter = 4
    case saturn = 5
    case uranus = 6
    case neptune = 7
  }

  enum ErrorCode: Int {
    case notEnoughMemory
    case invalidResource
    case timeOut
  }

  // 正确实例
  enum ErrorType: String {
    case error
    case warning
  }

  /// 特定需要
  // swiftlint:disable redundant_string_enum_value
  enum UserType: String {
    case owner = "owner"
    case manager = "manager"
    case member = "member"
  }
  // swiftlint:enable redundant_string_enum_value

  enum Planet: Int {
    case mercury
    case venus
    case earth
    case mars
    case jupiter
    case saturn
    case uranus
    case neptune
  }
  ```

  </details>
  
* **默认使用 `static` 作为类型函数** 若支持重写，则要使用 `class` 关键字.

  <details>
  <summary>示例</summary>

  ```swift
  
  // 错误示例
  class Fruit {
    class func eatFruits(_ fruits: [Fruit]) { ... }
  }

  // 错误示例
  class Fruit {
    static func eatFruits(_ fruits: [Fruit]) { ... }
  }
  ```

  </details>

* **默认使用 `final` 修饰 `class`类型.** 该规则会明确告诉编译器取消对该class类型的动态派发优化, 其函数会使用直接派发方式.

  <details>
  <summary>示例</summary>

  ```swift
  // 错误示例
  class SettingsRepository {
    // ...
  }

  // 正确示例
  final class SettingsRepository {
    // ...
  }
  ```

  </details>

* **在不使用 `optinal binding`值时，则检查其是否为空.**

  <details>
  <summary>示例</summary>

  ```swift
  var thing: Thing?

  // 错误示例
  if let _ = thing {
    doThing()
  }

  // 正确示例
  if thing != nil {
    doThing()
  }
  ```

  </details>

**[⬆ 返回顶部](#目录)**

## 与Objc的交互

* **在非必要情况下class无需继承 `NSObject`.** 如果需要使用Objc特性, 则按照需添加 `@objc` 修饰.

  <details>
  <summary>示例</summary>

  ```swift
  // 标准示例
  class PriceBreakdownViewController {

    private let acceptButton = UIButton()

    private func setUpAcceptButton() {
      acceptButton.addTarget(
        self,
        action: #selector(didTapAcceptButton),
        forControlEvents: .TouchUpInside)
    }

    @objc
    private func didTapAcceptButton() {
      // ...
    }
  }
  ```

  </details>

**[⬆ 返回顶部](#目录)**