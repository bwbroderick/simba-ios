import SwiftUI

struct EmptyStateView: View {
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 8) {
            Text(title)
                .font(.headline.weight(.semibold))
                .foregroundColor(.black)
            Text(message)
                .font(.subheadline)
                .foregroundColor(.gray)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 24)
    }
}

#Preview {
    EmptyStateView(title: "Inbox empty", message: "Pull to refresh or wait for new mail.")
}
