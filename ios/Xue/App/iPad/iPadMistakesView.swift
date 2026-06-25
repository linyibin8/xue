import SwiftUI

// iPad 错题本：左栏错题列表（待复习 + 最近），右栏错题详情。
// 数据源 = 复习队列（AppState.dueReviewItems / recentReviewItems，来自 /api/review-queue），
// 无需新增后端接口。条目模型 ReviewMistakeItem 已含题面/作答/订正/知识点等完整字段。

struct iPadMistakesView: View {
    @ObservedObject var state: AppState
    @State private var selectedId: String?

    private var allItems: [ReviewMistakeItem] {
        state.dueReviewItems + state.recentReviewItems
    }

    private var selected: ReviewMistakeItem? {
        allItems.first { $0.id == selectedId }
    }

    var body: some View {
        NavigationStack {
            HStack(spacing: 0) {
                list
                    .frame(width: 380)
                Divider()
                detailPane
                    .frame(maxWidth: .infinity)
            }
            .navigationTitle("错题本")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        Task { await state.refreshReviewQueuePreview() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                }
            }
        }
        .task { await state.refreshReviewQueuePreview() }
    }

    private var list: some View {
        Group {
            if allItems.isEmpty {
                ContentUnavailableCompat(title: "暂无错题", systemImage: "checkmark.seal", message: "学习中点「加入错题本」后会出现在这里。")
            } else {
                List(selection: $selectedId) {
                    if !state.dueReviewItems.isEmpty {
                        Section("待复习") {
                            ForEach(state.dueReviewItems, id: \.id) { row($0) }
                        }
                    }
                    if !state.recentReviewItems.isEmpty {
                        Section("最近") {
                            ForEach(state.recentReviewItems, id: \.id) { row($0) }
                        }
                    }
                }
                .listStyle(.sidebar)
            }
        }
        .background(Color(.secondarySystemBackground))
    }

    private func row(_ item: ReviewMistakeItem) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(item.title.isEmpty ? item.questionText : item.title)
                .font(.subheadline.weight(.semibold))
                .lineLimit(2)
            HStack(spacing: 6) {
                if !item.subject.isEmpty {
                    tag(item.subject, color: .blue)
                }
                if item.isDue {
                    tag("待复习", color: .orange)
                }
                if !item.errorType.isEmpty {
                    tag(item.errorType, color: .red)
                }
            }
        }
        .padding(.vertical, 2)
        .tag(item.id)
    }

    private func tag(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.caption2.weight(.medium))
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(color.opacity(0.15), in: Capsule())
            .foregroundStyle(color)
    }

    private var detailPane: some View {
        Group {
            if let item = selected {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        Text(item.title.isEmpty ? "错题详情" : item.title)
                            .font(.title2.weight(.bold))
                        HStack(spacing: 8) {
                            if !item.subject.isEmpty { tag(item.subject, color: .blue) }
                            if !item.locationRef.isEmpty { tag(item.locationRef, color: .gray) }
                            tag("已复习 \(item.reviewCount) 次", color: .green)
                        }
                        field("题目", item.questionText)
                        field("我的作答", item.studentAnswer)
                        field("正确答案", item.expectedAnswer)
                        field("错误原因", item.errorReason)
                        field("订正", item.correction)
                        field("下一步", item.nextAction)
                        if !item.knowledgePoints.isEmpty {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("知识点").font(.headline)
                                FlowTags(tags: item.knowledgePoints)
                            }
                        }
                    }
                    .padding(24)
                    .frame(maxWidth: 820, alignment: .leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                ContentUnavailableCompat(title: "选择一道错题", systemImage: "sidebar.right", message: "在左侧选择一道错题查看详情。")
            }
        }
        .background(Color(.systemGroupedBackground))
    }

    @ViewBuilder
    private func field(_ label: String, _ value: String) -> some View {
        if !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text(label).font(.headline)
                Text(value)
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 14))
        }
    }
}

// 简易自适应标签流（知识点）
struct FlowTags: View {
    let tags: [String]
    var body: some View {
        let columns = [GridItem(.adaptive(minimum: 80), spacing: 8)]
        LazyVGrid(columns: columns, alignment: .leading, spacing: 8) {
            ForEach(tags, id: \.self) { t in
                Text(t)
                    .font(.caption.weight(.medium))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.accentColor.opacity(0.12), in: Capsule())
                    .foregroundStyle(Color.accentColor)
            }
        }
    }
}
