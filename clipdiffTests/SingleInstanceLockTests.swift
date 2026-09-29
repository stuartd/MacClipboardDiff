import Darwin
import Foundation
import XCTest
@testable import ClipDiffCore

final class SingleInstanceLockTests: XCTestCase {
    func testOnlyOneOwnerAndContenderReadsItsPID() throws {
        try withLockURL { url in
            let owner = try SingleInstanceLock(url: url)
            let contender = try SingleInstanceLock(url: url)
            XCTAssertTrue(owner.isOwner)
            XCTAssertFalse(contender.isOwner)
            XCTAssertEqual(contender.ownerProcessIdentifier, getpid())
            withExtendedLifetime(owner) {}
        }
    }

    func testClosingOwnerAllowsNewOwnerEvenWithContenderStillOpen() throws {
        try withLockURL { url in
            var owner: SingleInstanceLock? = try SingleInstanceLock(url: url)
            let contender = try SingleInstanceLock(url: url)
            XCTAssertTrue(owner!.isOwner)
            XCTAssertFalse(contender.isOwner)
            owner = nil

            let replacement = try SingleInstanceLock(url: url)
            XCTAssertTrue(replacement.isOwner)
            XCTAssertFalse(try SingleInstanceLock(url: url).isOwner)
            withExtendedLifetime((contender, replacement)) {}
        }
    }

    func testStalePIDDoesNotPreventAcquiringAnUnlockedFile() throws {
        try withLockURL { url in
            try Data("999999999".utf8).write(to: url)
            let owner = try SingleInstanceLock(url: url)
            XCTAssertTrue(owner.isOwner)
            XCTAssertEqual(owner.ownerProcessIdentifier, getpid())
            XCTAssertEqual(try String(contentsOf: url), String(getpid()))
        }
    }

    func testNewLockFileIsPrivate() throws {
        try withLockURL { url in
            let owner = try SingleInstanceLock(url: url)
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            XCTAssertEqual((attributes[.posixPermissions] as? NSNumber)?.intValue, 0o600)
            withExtendedLifetime(owner) {}
        }
    }

    func testSymlinkIsRejectedWithoutModifyingTarget() throws {
        try withLockURL { url in
            let target = url.appendingPathExtension("target")
            try Data("untouched".utf8).write(to: target)
            try FileManager.default.createSymbolicLink(at: url, withDestinationURL: target)
            XCTAssertThrowsError(try SingleInstanceLock(url: url))
            XCTAssertEqual(try String(contentsOf: target), "untouched")
        }
    }

    func testMissingParentIsAnErrorInsteadOfDuplicateInstance() throws {
        try withLockURL { url in
            XCTAssertThrowsError(try SingleInstanceLock(url: url.appendingPathComponent("missing")))
        }
    }

    private func withLockURL(_ test: (URL) throws -> Void) throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ClipDiffLockTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try test(directory.appendingPathComponent("instance.lock"))
    }
}
