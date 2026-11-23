import Foundation
import SwiftUI
import Combine

/// 直播 ViewModel
@MainActor
class LiveViewModel: ObservableObject {
    /// 全部频道分组。
    @Published var channelGroups: [LiveChannelGroup] = []
    /// 当前选中分组索引。
    @Published var selectedGroupIndex: Int = 0
    /// 当前选中频道索引（相对于当前分组）。
    @Published var selectedChannelIndex: Int = 0
    /// 当前播放频道。
    @Published var currentChannel: LiveChannelItem?
    /// 当前频道节目单（预留）。
    @Published var epgList: [Epginfo] = []
    /// 加载状态（预留，便于后续接入远程 EPG）。
    @Published var isLoading = false
    /// 是否显示频道列表（预留给 TV 遥控交互）。
    @Published var showChannelList = false
    
    /// 订阅配置更新，支持直播频道列表实时刷新。
    private var cancellables: Set<AnyCancellable> = []
    
    init() {
        bindLiveChannelGroups()
    }
    
    /// 加载直播频道
    func loadChannels() {
        applyChannelGroups(ApiConfig.shared.liveChannelGroupList)
    }
    
    /// 选择频道分组
    func selectGroup(_ index: Int) {
        guard index >= 0, index < channelGroups.count else { return }
        selectedGroupIndex = index
        selectedChannelIndex = 0
        if let first = channelGroups[index].channels.first {
            selectChannel(first)
        }
    }
    
    /// 选择频道
    func selectChannel(_ channel: LiveChannelItem) {
        for (groupIndex, group) in channelGroups.enumerated() {
            if let index = group.channels.firstIndex(where: { $0.id == channel.id && $0.channelUrls == channel.channelUrls }) {
                selectedGroupIndex = groupIndex
                selectedChannelIndex = index
                break
            }
        }
        currentChannel = channel
        loadEPG(for: channel)
    }
    
    /// Walk only playable entries, wrapping across empty groups safely.
    func previousChannel() { stepChannel(-1) }
    func nextChannel() { stepChannel(1) }

    private func stepChannel(_ delta: Int) {
        let entries = channelGroups.enumerated().flatMap { group, value in
            value.channels.enumerated().map { (group, $0.offset, $0.element) }
        }
        guard !entries.isEmpty else { return }
        let position = entries.firstIndex {
            $0.0 == selectedGroupIndex && $0.1 == selectedChannelIndex
        } ?? 0
        let target = entries[(position + delta + entries.count) % entries.count]
        selectedGroupIndex = target.0
        selectedChannelIndex = target.1
        selectChannel(target.2)
    }

    /// 切换线路
    func switchSource() {
        // `currentChannel` 为值类型，调用 mutating 方法会触发 @Published 重新发布。
        currentChannel?.nextSource()
    }
    
    func selectSource(at index: Int) {
        guard let channel = currentChannel, channel.channelUrls.indices.contains(index) else { return }
        currentChannel?.sourceIndex = index
    }

    /// 当前频道列表
    var currentChannels: [LiveChannelItem] {
        guard selectedGroupIndex < channelGroups.count else { return [] }
        return channelGroups[selectedGroupIndex].channels
    }
    
    /// 加载 EPG 节目单
    private func loadEPG(for channel: LiveChannelItem) {
        // 预留：后续可在此按频道名/频道 ID 请求远程 EPG。
        // 当前版本先清空，避免展示过期节目单。
        epgList = []
    }
    
    private func bindLiveChannelGroups() {
        ApiConfig.shared.$liveChannelGroupList
            .sink { [weak self] groups in
                self?.applyChannelGroups(groups)
            }
            .store(in: &cancellables)
    }
    
    private func applyChannelGroups(_ groups: [LiveChannelGroup]) {
        let previousChannelId = currentChannel?.id
        channelGroups = groups
        
        guard !groups.isEmpty else {
            selectedGroupIndex = 0
            selectedChannelIndex = 0
            currentChannel = nil
            return
        }
        
        if let previousChannelId,
           let located = locateChannel(withId: previousChannelId, in: groups) {
            selectedGroupIndex = located.groupIndex
            selectedChannelIndex = located.channelIndex
            currentChannel = groups[located.groupIndex].channels[located.channelIndex]
            return
        }
        
        let clampedGroupIndex = min(max(0, selectedGroupIndex), groups.count - 1)
        selectedGroupIndex = clampedGroupIndex
        
        let channels = groups[clampedGroupIndex].channels
        guard !channels.isEmpty else {
            selectedChannelIndex = 0
            currentChannel = nil
            return
        }
        
        let clampedChannelIndex = min(max(0, selectedChannelIndex), channels.count - 1)
        selectedChannelIndex = clampedChannelIndex
        currentChannel = channels[clampedChannelIndex]
    }
    
    private func locateChannel(
        withId channelId: String,
        in groups: [LiveChannelGroup]
    ) -> (groupIndex: Int, channelIndex: Int)? {
        for (groupIndex, group) in groups.enumerated() {
            if let channelIndex = group.channels.firstIndex(where: { $0.id == channelId }) {
                return (groupIndex, channelIndex)
            }
        }
        return nil
    }
}

// 安全数组下标访问
extension Collection {
    /// 安全下标读取，越界时返回 `nil`。
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
