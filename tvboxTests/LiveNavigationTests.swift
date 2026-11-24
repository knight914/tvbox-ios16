import XCTest
@testable import TVBox

@MainActor
final class LiveNavigationTests: XCTestCase {
    private func channel(_ name: String, index: Int, route: String) -> LiveChannelItem {
        var item = LiveChannelItem(channelName: name, channelIndex: index)
        item.channelUrls = ["https://example.invalid/\(route)"]
        return item
    }

    func testSubscriptionReplacementClearsOldChannelAndEPG() {
        let config = ApiConfig.shared
        let original = config.liveChannelGroupList
        defer { config.liveChannelGroupList = original }
        let vm = LiveViewModel()
        var first = LiveChannelGroup(groupName: "First")
        first.channels = [channel("Same", index: 0, route: "old")]
        config.liveChannelGroupList = [first]
        var second = LiveChannelGroup(groupName: "Second")
        second.channels = [channel("Same", index: 0, route: "new")]
        config.liveChannelGroupList = [second]
        XCTAssertEqual(vm.currentChannel?.currentUrl, second.channels[0].currentUrl)
        XCTAssertTrue(vm.epgList.isEmpty)
        config.liveChannelGroupList = []
        XCTAssertNil(vm.currentChannel)
        XCTAssertEqual(vm.selectedGroupIndex, 0)
        XCTAssertTrue(vm.epgList.isEmpty)
    }
    func testPickerSynchronizesIndexesAndWrapsAcrossEmptyGroups() {
        let vm = LiveViewModel()
        let a = channel("A", index: 0, route: "a")
        let b = channel("B", index: 0, route: "b")
        var first = LiveChannelGroup(groupName: "One")
        first.channels = [a]
        var last = LiveChannelGroup(groupName: "Three")
        last.channels = [b]
        vm.channelGroups = [first, LiveChannelGroup(groupName: "Empty"), last]
        vm.selectChannel(b)
        XCTAssertEqual(vm.selectedGroupIndex, 2)
        XCTAssertEqual(vm.selectedChannelIndex, 0)
        vm.nextChannel()
        XCTAssertEqual(vm.currentChannel?.channelName, "A")
        vm.previousChannel()
        XCTAssertEqual(vm.currentChannel?.channelName, "B")
        XCTAssertEqual(vm.selectedGroupIndex, 2)
    }

    func testDuplicateNamesInDifferentGroupsKeepCorrectRoute() {
        let vm = LiveViewModel()
        let a = channel("News", index: 0, route: "a")
        let b = channel("News", index: 0, route: "b")
        var first = LiveChannelGroup(groupName: "One")
        first.channels = [a]
        var second = LiveChannelGroup(groupName: "Two")
        second.channels = [b]
        vm.channelGroups = [first, second]
        vm.selectChannel(b)
        XCTAssertEqual(vm.selectedGroupIndex, 1)
        vm.previousChannel()
        XCTAssertEqual(vm.currentChannel?.currentUrl, a.currentUrl)
    }

    func testEmptyGroupsAndRealLineCyclingAreSafe() {
        let vm = LiveViewModel()
        vm.channelGroups = [LiveChannelGroup(groupName: "Empty")]
        vm.currentChannel = nil
        vm.nextChannel()
        vm.previousChannel()
        XCTAssertNil(vm.currentChannel)
        var item = channel("One", index: 0, route: "a")
        item.channelUrls.append("https://example.invalid/backup")
        vm.selectChannel(item)
        vm.switchSource()
        XCTAssertEqual(vm.currentChannel?.currentUrl, "https://example.invalid/backup")
        vm.switchSource()
        XCTAssertEqual(vm.currentChannel?.sourceIndex, 0)
        XCTAssertEqual(vm.currentChannel?.sourceNum, 2)
    }
}
