import XCTest

import picaroonTests

var tests = [XCTestCaseEntry]()
tests += picaroonTests.allTests()
XCTMain(tests)
