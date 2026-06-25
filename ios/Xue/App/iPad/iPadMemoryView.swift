import SwiftUI

// iPad 记忆：长期记忆画像 + 记忆事件流。复用 AppState.refreshMemoryDigest /
// memoryProfileText / memoryEvents（来自 /api/memory）。

struct iPadMemoryView: View {
    @ObservedObject var state: AppState

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    profileCard
                    if !state.memoryEvents.isEmpty {
                        Text("记忆事件")
                            .font(.title3.weight(.semibold))
                        ForEach(state.memoryEvents) { event in
                            eventCard(event)
                        }
                    } else if !state.isLoadingMemoryDigest {
                        ContentUnavailableCompat(title: "暂无记忆", systemImage: "brain", message: "学习中点「形成记忆」后，AI 会在这里沉淀对你的了解。")
                            .frame(height: 220)
                    }
                }
                .padding(24)
                .frame(maxWidth: 880, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("记忆")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        Task { await state.refreshMemoryDigest(force: true) }
                    } label: {
                        if state.isLoadingMemoryDigest {
                            ProgressView()
                        } else {
                            Image(systemName: "arrow.clockwise")
                        }
                    }
                }
            }
        }
        .task { await state.refreshMemoryDigest() }
    }

    private var profileCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("学习画像", systemImage: "person.text.rectangle")
                .font(.headline)
            if state.memoryProfileText.isEmpty {
                Text("尚未形成画像。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                Text(state.memoryProfileText)
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !state.memoryProfileUpdatedAt.isEmpty {
                Text("更新于 \(state.memoryProfileUpdatedAt)")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 16))
    }

    private func eventCard(_ event: MemoryEvent) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: iconFor(event))
                    .foregroundStyle(.tint)
                Text(labelFor(event))
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text(event.createdAt)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            Text(event.text)
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 14))
    }

    private func iconFor(_ event: MemoryEvent) -> String {
        switch event.messageType {
        case "mistake": return "exclamationmark.bubble"
        case "memory": return "brain.head.profile"
        default: return "sparkle"
        }
    }

    private func labelFor(_ event: MemoryEvent) -> String {
        switch event.messageType {
        case "mistake": return "错题"
        case "memory": return "记忆"
        default: return event.source.isEmpty ? "记录" : event.source
        }
    }
}
