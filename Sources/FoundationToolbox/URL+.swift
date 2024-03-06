//
//  URL+.swift
//  ClassDumper
//
//  Created by JH on 2024/2/24.
//

import Foundation
import FrameworkToolbox

extension FrameworkToolbox where Base == URL {
    public struct DirectorySequence: Sequence {
        let enumerator: FileManager.DirectoryEnumerator?

        init(url: URL, includingPropertiesForKeys keys: [URLResourceKey]?, options mask: FileManager.DirectoryEnumerationOptions = []) {
            let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: keys, options: mask)
            self.enumerator = enumerator
        }

        public func makeIterator() -> AnyIterator<URL> {
            .init {
                enumerator?.nextObject() as? URL
            }
        }
    }

    public func enumerator(includingPropertiesForKeys keys: [URLResourceKey]? = nil, options mask: FileManager.DirectoryEnumerationOptions = []) -> DirectorySequence {
        return .init(url: base, includingPropertiesForKeys: keys, options: mask)
    }
}
