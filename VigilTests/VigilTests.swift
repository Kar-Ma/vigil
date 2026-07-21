//
//  VigilTests.swift
//  VigilTests
//
//  Created by Karthik Mahadevan on 21/07/2026.
//

import Foundation
import Testing
@testable import Vigil

struct VigilTests {

    @Test func emergencyNumberKeepsOnlyEightDigits() {
        #expect(EmergencyCallHandoff.sanitizedNumber(" 112 ") == "112")
        #expect(EmergencyCallHandoff.sanitizedNumber("9-1-1") == "911")
        #expect(EmergencyCallHandoff.sanitizedNumber("123456789") == "12345678")
    }

    @Test func emergencyCallRequiresANumber() {
        #expect(EmergencyCallHandoff.phoneURL(for: "") == nil)
        #expect(EmergencyCallHandoff.phoneURL(for: "911")?.absoluteString == "tel:911")
    }

}
