//
//  RecursiveLock.swift
//  ClassDumper
//
//  Created by JH on 2024/2/24.
//

import Foundation

@propertyWrapper
public final class Lock<Value> {
    private var _wrappedValue: Value

    private let lock = NSLock()

    public var wrappedValue: Value {
        set {
            lock.withLock {
                _wrappedValue = newValue
            }
        }
        get {
            lock.withLock {
                _wrappedValue
            }
        }
    }

    public init(wrappedValue: Value) {
        self._wrappedValue = wrappedValue
    }
}

@propertyWrapper
public final class RecursiveLock<Value> {
    private var _wrappedValue: Value

    private let recursiveLock = NSRecursiveLock()

    public var wrappedValue: Value {
        set {
            recursiveLock.withLock {
                _wrappedValue = newValue
            }
        }
        get {
            recursiveLock.withLock {
                _wrappedValue
            }
        }
    }

    public init(wrappedValue: Value) {
        self._wrappedValue = wrappedValue
    }
}
