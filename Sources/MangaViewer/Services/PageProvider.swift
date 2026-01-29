import AppKit
import Foundation

protocol PageProvider: Sendable {
    var pageCount: Int { get }
    func image(at index: Int) async throws -> NSImage
    func close()
}
