import XCTest

#if !canImport(ObjectiveC)
public func allTests() -> [XCTestCaseEntry] {
    return [
        testCase(picaroonBadClientTests.allTests),
        testCase(picaroonConnectionTests.allTests),
        testCase(picaroonServicesTests.allTests),
    ]
}
#endif
