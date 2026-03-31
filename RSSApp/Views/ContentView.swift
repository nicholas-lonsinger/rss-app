import SwiftUI

struct ContentView: View {
    @State private var viewModel = FeedViewModel()

    var body: some View {
        NavigationStack {
            ArticleListView(viewModel: viewModel)
        }
    }
}

#Preview {
    ContentView()
}
