//
//  RecursiveLock.swift
//  ClassDumper
//
//  Created by JH on 2024/2/24.
//

import Foundation

@propertyWrapper
public final class Lock<Value>: @unchecked Sendable {
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

extension Lock: Equatable where Value: Equatable {
    public static func == (lhs: Lock, rhs: Lock) -> Bool {
        lhs.wrappedValue == rhs.wrappedValue
    }
}

extension Lock: Hashable where Value: Hashable {
    public func hash(into hasher: inout Hasher) {
        hasher.combine(wrappedValue)
    }
}

extension Lock: Codable where Value: Codable {
    public convenience init(from decoder: any Decoder) throws {
        self.init(wrappedValue: try Value(from: decoder))
    }
    
    public func encode(to encoder: any Encoder) throws {
        try wrappedValue.encode(to: encoder)
    }
}


@propertyWrapper
public final class RecursiveLock<Value>: @unchecked Sendable {
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

extension RecursiveLock: Equatable where Value: Equatable {
    public static func == (lhs: RecursiveLock, rhs: RecursiveLock) -> Bool {
        lhs.wrappedValue == rhs.wrappedValue
    }
}

extension RecursiveLock: Hashable where Value: Hashable {
    public func hash(into hasher: inout Hasher) {
        hasher.combine(wrappedValue)
    }
}

extension RecursiveLock: Codable where Value: Codable {
    public convenience init(from decoder: any Decoder) throws {
        self.init(wrappedValue: try Value(from: decoder))
    }
    
    public func encode(to encoder: any Encoder) throws {
        try wrappedValue.encode(to: encoder)
    }
}
