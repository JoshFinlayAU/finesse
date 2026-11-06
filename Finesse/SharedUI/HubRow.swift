import SwiftUI

/// A titled, horizontally scrolling row. The focus section keeps vertical moves on the row below
/// from jumping sideways, wherever the user has scrolled to.
struct HubRow<Item: Identifiable, Card: View>: View {
    let title: String
    let items: [Item]
    @ViewBuilder let card: (Item) -> Card

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text(title)
                .font(.title3)
                .fontWeight(.semibold)
            ScrollView(.horizontal) {
                LazyHStack(alignment: .top, spacing: 48) {
                    ForEach(items) { item in
                        card(item)
                    }
                }
            }
            .scrollClipDisabled()
            .scrollIndicators(.hidden)
            .focusSection()
        }
    }
}
