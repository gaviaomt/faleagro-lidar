//
//  StrayScannerTests.swift
//  FaleAgro LiDAR
//
//  Confere as contas do dossel sem câmera. A captura no iPhone não é simulada aqui.
//

import XCTest
@testable import StrayScanner

final class CanopyMathTests: XCTestCase {
    func testContasDoDossel() {
        let failures = CanopySelfTest.failures()
        XCTAssertTrue(failures.isEmpty, failures.joined(separator: "\n"))
    }
}
