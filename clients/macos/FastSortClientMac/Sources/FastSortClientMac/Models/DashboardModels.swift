import Foundation

struct UserStatsResponse: Decodable {
    let printedTagCount: FlexibleInt?
    let orderCount: FlexibleInt?
    let userRoomCount: FlexibleInt?
    let tagTemplateCount: FlexibleInt?
    let blackListCount: FlexibleInt?
}

struct TrendRequest: Encodable {
    let startTime: String
    let endTime: String
}

struct TrendResponse: Decodable {
    let legend: [String]?
    let xAxis: [String]?
    let series: [TrendSeries]?

    init(legend: [String]? = nil, xAxis: [String]? = nil, series: [TrendSeries]? = nil) {
        self.legend = legend
        self.xAxis = xAxis
        self.series = series
    }

    enum CodingKeys: String, CodingKey {
        case legend
        case xAxis
        case xaxis
        case series
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        legend = try container.decodeFlexibleStringArrayIfPresent(forKey: .legend)
        xAxis = try container.decodeFlexibleStringArrayIfPresent(forKey: .xAxis)
            ?? container.decodeFlexibleStringArrayIfPresent(forKey: .xaxis)
        series = try container.decodeIfPresent([TrendSeries].self, forKey: .series)
    }
}

struct TrendSeries: Decodable, Identifiable {
    var id: String { name ?? UUID().uuidString }
    let name: String?
    let data: [Double]?

    enum CodingKeys: String, CodingKey {
        case name
        case data
    }

    init(name: String?, data: [Double]?) {
        self.name = name
        self.data = data
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decodeIfPresent(String.self, forKey: .name)
        if let values = try? container.decodeIfPresent([FlexibleDouble].self, forKey: .data) {
            data = values.map(\.value)
        } else {
            data = []
        }
    }
}

private extension KeyedDecodingContainer {
    func decodeFlexibleStringArrayIfPresent(forKey key: Key) throws -> [String]? {
        guard let values = try? decodeIfPresent([FlexibleString].self, forKey: key) else {
            return nil
        }
        return values.compactMap(\.value)
    }
}

struct RoomListItem: Decodable, Identifiable {
    let id: String?
    let roomName: String?
    let roomNumber: String?
    let roomUrl: String?
    let liveType: FlexibleString?
    let liveSession: String?
    let eid: String?
    let ksWsPath: String?
    let wsPath: String?

    var displayName: String {
        if let roomName, !roomName.isEmpty { return roomName }
        if let roomNumber, !roomNumber.isEmpty { return roomNumber }
        return "直播间"
    }

    var handle: String {
        guard let roomNumber, !roomNumber.isEmpty else { return "" }
        return "#\(roomNumber)"
    }

    var avatarURL: URL? {
        guard let roomUrl, !roomUrl.isEmpty else { return nil }
        return URL(string: roomUrl)
    }

    enum CodingKeys: String, CodingKey {
        case id
        case roomName
        case name
        case title
        case roomNumber
        case roomNo
        case roomId
        case eid
        case roomUrl
        case avatar
        case cover
        case liveType
        case platformType
        case platform
        case source
        case liveSession
        case ksWsPath
        case wsPath
    }

    init(
        id: String?,
        roomName: String?,
        roomNumber: String?,
        roomUrl: String?,
        liveType: FlexibleString?,
        liveSession: String?,
        eid: String?,
        ksWsPath: String?,
        wsPath: String?
    ) {
        self.id = id
        self.roomName = roomName
        self.roomNumber = roomNumber
        self.roomUrl = roomUrl
        self.liveType = liveType
        self.liveSession = liveSession
        self.eid = eid
        self.ksWsPath = ksWsPath
        self.wsPath = wsPath
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(FlexibleString.self, forKey: .id)?.value
        roomName = try container.decodeIfPresent(String.self, forKey: .roomName)
            ?? container.decodeIfPresent(String.self, forKey: .name)
            ?? container.decodeIfPresent(String.self, forKey: .title)
        roomNumber = try container.decodeIfPresent(FlexibleString.self, forKey: .roomNumber)?.value
            ?? container.decodeIfPresent(FlexibleString.self, forKey: .roomNo)?.value
            ?? container.decodeIfPresent(FlexibleString.self, forKey: .roomId)?.value
        roomUrl = try container.decodeIfPresent(String.self, forKey: .roomUrl)
            ?? container.decodeIfPresent(String.self, forKey: .avatar)
            ?? container.decodeIfPresent(String.self, forKey: .cover)
        liveType = try container.decodeIfPresent(FlexibleString.self, forKey: .liveType)
            ?? container.decodeIfPresent(FlexibleString.self, forKey: .platformType)
            ?? container.decodeIfPresent(FlexibleString.self, forKey: .platform)
            ?? container.decodeIfPresent(FlexibleString.self, forKey: .source)
        liveSession = try container.decodeIfPresent(String.self, forKey: .liveSession)
        eid = try container.decodeIfPresent(FlexibleString.self, forKey: .eid)?.value
        ksWsPath = try container.decodeIfPresent(String.self, forKey: .ksWsPath)
        wsPath = try container.decodeIfPresent(String.self, forKey: .wsPath)
    }
}

struct PageResponse<Item: Decodable>: Decodable {
    let list: [Item]?
    let total: FlexibleInt?
    let totalCount: FlexibleInt?
    let count: FlexibleInt?
    let pages: FlexibleInt?
    let totalPages: FlexibleInt?
    let pageTotal: FlexibleInt?
    let pageCount: FlexibleInt?

    var totalValue: Int {
        total?.value ?? totalCount?.value ?? count?.value ?? 0
    }

    var pagesValue: Int {
        pages?.value ?? totalPages?.value ?? pageTotal?.value ?? pageCount?.value ?? 0
    }
}

struct BlacklistItem: Decodable, Identifiable {
    let id: String?
    let orderName: String?
    let liveType: FlexibleString?
    let blackType: FlexibleString?
    let blackLevel: FlexibleInt?
    let skipBillCount: FlexibleInt?
    let skipBillAmount: FlexibleString?
    let createdTime: String?
    let updatedTime: String?
    let blackDetailVoListde: [BlacklistDetailItem]?
    let blackDetailVoList: [BlacklistDetailItem]?
}

struct BlacklistDetailItem: Decodable, Identifiable {
    let id: String?
    let orderName: String?
    let blackType: FlexibleString?
    let skipBillAmount: FlexibleString?
    let blackRemark: String?
    let createdUser: String?
    let updatedTime: String?
}

struct SortBatchAggregate: Decodable {
    let notComplete: SortBatchItem?
    let historyCompletedPage: PageResponse<SortBatchItem>?

    enum CodingKeys: String, CodingKey {
        case notComplete = "NOT_COMPLETE"
        case historyCompletedPage = "HISTORY_COMPLETED_PAGE"
    }
}

struct SortBatchItem: Decodable, Identifiable {
    let id: String?
    let batchName: String?
    let sortStatus: FlexibleString?
    let createdTime: String?
}

struct LiveTagItem: Decodable, Identifiable {
    let id: String?
    let tagId: String?
    let orderName: String?
    let orderNameId: String?
    let shortId: String?
    let danmuUserId: String?
    let remarkBuyerId: String?
    let orderNumber: FlexibleString?
    let orderIndex: FlexibleString?
    let orderAmounts: FlexibleString?
    let orderCount: FlexibleString?
    let cachedUserId: String?
    let cachedNicknameMask: String?
    let cachedVerifiedAt: String?
    let cacheShopKey: String?
    let cacheVersion: String?
    let createdTime: String?
    let updatedTime: String?
    let isBackList: Bool?
}

struct LiveRecordResponse: Decodable {
    let id: String?
    let sortBatchId: String?
}

struct VipOrderItem: Decodable, Identifiable {
    let id: String?
    let vipInfoName: String?
    let vipInfoDuration: FlexibleString?
    let vipAddType: String?
    let vipStartTime: String?
    let vipEndTime: String?
    let paymentPrice: FlexibleString?
    let paymentStatus: FlexibleInt?
    let createdTime: String?
}

struct VipInfoItem: Decodable, Identifiable {
    let id: String?
    let vipName: String?
    let price: FlexibleString?
    let discountedPrice: FlexibleString?
    let duration: FlexibleInt?
    let discount: FlexibleString?
}

struct TagTemplateItem: Decodable, Identifiable {
    let id: String?
    let tagTemplateName: String?
    let templateLayout: String?
}

struct DanmuTemplateItem: Decodable, Identifiable {
    let id: String?
    let danmuTemplateName: String?
}

struct DanmuMappingItem: Decodable, Identifiable {
    let id: String?
    let danmuMappingName: String?
    let danmuMappingElement: String?
}

struct SortSettingResponse: Decodable {
    let id: String?
    let shelfNumberRange: String?
    let isRefreshIndexNumber: FlexibleInt?
}

struct BlacklistUserSettingResponse: Decodable {
    let id: String?
    let isPrintFlag: FlexibleInt?
    let blackLevel: FlexibleInt?
}

struct FlexibleString: Decodable, Equatable {
    let value: String?

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            value = nil
            return
        }
        if let stringValue = try? container.decode(String.self) {
            value = stringValue
            return
        }
        if let intValue = try? container.decode(Int.self) {
            value = String(intValue)
            return
        }
        if let doubleValue = try? container.decode(Double.self) {
            value = String(doubleValue)
            return
        }
        value = nil
    }
}

struct FlexibleDouble: Decodable, Equatable {
    let value: Double

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            value = 0
            return
        }
        if let doubleValue = try? container.decode(Double.self) {
            value = doubleValue
            return
        }
        if let intValue = try? container.decode(Int.self) {
            value = Double(intValue)
            return
        }
        if let stringValue = try? container.decode(String.self) {
            value = Double(stringValue.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
            return
        }
        value = 0
    }
}
