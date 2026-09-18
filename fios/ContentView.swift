import SwiftUI
import Playgrounds

struct ContentView: View {
    var body: some View {
        VStack(spacing: 20) {
                    Text("Hello iOS")
                        .font(.largeTitle)

                    Button("点我") {
                        print("按钮被点击了")
                    }
                    .buttonStyle(.borderedProminent)
                }
    }
}

#Preview {
    ContentView()
}

#Playground {
    _ = 1 + 2
}
