//
//  AssociatedValue.swift
//
//  Parts taken from:
//  github.com/bradhilton/AssociatedValues
//  Created by Skyvive
//  Created by Florian Zand on 23.02.23.
//

import Foundation
import ObjectiveC.runtime
import FrameworkToolbox

/**
 Returns the associated value for the specified object and key.

 - Parameters:
    - key: The key of the associated value.
    - object: The object of the associated value.
 - Returns: The associated value for the object and key, or `nil` if the value couldn't be found for the key.
 */
public func getAssociatedValue<T>(_ key: String, object: AnyObject) -> T? {
    (objc_getAssociatedObject(object, key.address) as? AssociatedValue)?.value as? T
}

/**
 Returns the associated value for the specified object, key and inital value.

 - Parameters:
    - key: The key of the associated value.
    - object: The object of the associated value.
    - initialValue: The inital value of the associated value.
 - Returns: The associated value for the object and key.
 */
public func getAssociatedValue<T>(_ key: String, object: AnyObject, initialValue: @autoclosure () -> T) -> T {
    getAssociatedValue(key, object: object) ?? setAndReturn(initialValue: initialValue(), key: key, object: object)
}

/**
 Returns the associated value for the specified object, key and inital value.

 - Parameters:
    - key: The key of the associated value.
    - object: The object of the associated value.
    - initialValue: The inital value of the associated value.
 - Returns: The associated value for the object and key.
 */
public func getAssociatedValue<T>(_ key: String, object: AnyObject, initialValue: () -> T) -> T {
    getAssociatedValue(key, object: object) ?? setAndReturn(initialValue: initialValue(), key: key, object: object)
}

/**
 Sets a associated value for the specified object and key.

 - Parameters:
    - associatedValue: The value of the associated value.
    - key: The key of the associated value.
    - object: The object of the associated value.
 */
public func setAssociatedValue<T>(_ value: T?, key: String, object: AnyObject) {
    set(associatedValue: AssociatedValue(value), key: key, object: object)
}

/**
 Sets a weak associated value for the specified object and key.

 - Parameters:
    - weakAssociatedValue: The weak value of the associated value.
    - key: The key of the associated value.
    - object: The object of the associated value.
 */
public func setAssociatedValue<T: AnyObject>(weak value: T?, key: String, object: AnyObject) {
    set(associatedValue: AssociatedValue(weak: value), key: key, object: object)
}

private func set(associatedValue: AssociatedValue, key: String, object: AnyObject) {
    objc_setAssociatedObject(object, key.address, associatedValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
}

private func setAndReturn<T>(initialValue: T, key: String, object: AnyObject) -> T {
    setAssociatedValue( initialValue, key: key, object: object)
    return initialValue
}


extension FrameworkToolbox where Base: NSObject {
    /**
     Returns the associated value for the specified  key.

     - Parameters:
        - key: The key of the associated value.
     - Returns: The associated value for the key, or `nil` if the value couldn't be found for the key.
     */
    public func getAssociatedValue<T>(_ key: String) -> T? {
        FoundationToolbox.getAssociatedValue(key, object: base)
    }
    
    /**
     Returns the associated value for the specified key and inital value.

     - Parameters:
        - key: The key of the associated value.
        - initialValue: The inital value of the associated value.
     - Returns: The associated value for the object and key.
     */
    public func getAssociatedValue<T>(_ key: String, initialValue: @autoclosure () -> T) -> T {
        FoundationToolbox.getAssociatedValue(key, object: base, initialValue: initialValue)
    }
    
    /**
     Returns the associated value for the specified key and inital value.

     - Parameters:
        - key: The key of the associated value.
        - initialValue: The inital value of the associated value.
     - Returns: The associated value for the key.
     */
    public func getAssociatedValue<T>(_ key: String, initialValue: () -> T) -> T {
        FoundationToolbox.getAssociatedValue(key, object: base, initialValue: initialValue)
    }
    
    /**
     Sets an associated value for the specified key.

     - Parameters:
        - value: The value to set.
        - key: The key of the associated value.
     */
    public func setAssociatedValue<T>(_ value: T?, key: String) {
        FoundationToolbox.setAssociatedValue(value, key: key, object: base)
    }
    
    /**
     Sets a weak associated value for the specified key.

     - Parameters:
        - value: The weak value to set.
        - key: The key of the associated value.
     */
    public func setAssociatedValue<T: AnyObject>(weak value: T?, key: String) {
        FoundationToolbox.setAssociatedValue(weak: value, key: key, object: base)
    }
    
    /**
     Returns the associated value for the specified  key.

     - Parameters:
        - key: The key of the associated value.
     - Returns: The associated value for the key, or `nil` if the value couldn't be found for the key.
     */
    public static func getAssociatedValue<T>(_ key: String) -> T? {
        FoundationToolbox.getAssociatedValue(key, object: Base.self)
    }
    
    /**
     Returns the associated value for the specified key and inital value.

     - Parameters:
        - key: The key of the associated value.
        - initialValue: The inital value of the associated value.
     - Returns: The associated value for the object and key.
     */
    public static func getAssociatedValue<T>(_ key: String, initialValue: @autoclosure () -> T) -> T {
        FoundationToolbox.getAssociatedValue(key, object: Base.self, initialValue: initialValue)
    }
    
    /**
     Returns the associated value for the specified key and inital value.

     - Parameters:
        - key: The key of the associated value.
        - initialValue: The inital value of the associated value.
     - Returns: The associated value for the key.
     */
    public static func getAssociatedValue<T>(_ key: String, initialValue: () -> T) -> T {
        FoundationToolbox.getAssociatedValue(key, object: Base.self, initialValue: initialValue)
    }
    
    /**
     Sets an associated value for the specified key.

     - Parameters:
        - value: The value to set.
        - key: The key of the associated value.
     */
    public static func setAssociatedValue<T>(_ value: T?, key: String) {
        FoundationToolbox.setAssociatedValue(value, key: key, object: Base.self)
    }
    
    /**
     Sets a weak associated value for the specified key.

     - Parameters:
        - value: The weak value to set.
        - key: The key of the associated value.
     */
    public static func setAssociatedValue<T: AnyObject>(weak value: T?, key: String) {
        FoundationToolbox.setAssociatedValue(weak: value, key: key, object: Base.self)
    }
}

private class AssociatedValue {
    weak var _weakValue: AnyObject?
    var _value: Any?

    var value: Any? {
        _weakValue ?? _value
    }

    init(_ value: Any?) {
        _value = value
    }

    init(weak: AnyObject?) {
        _weakValue = weak
    }
}

private extension String {
    var address: UnsafeRawPointer {
        UnsafeRawPointer(bitPattern: abs(hashValue))!
    }
}
