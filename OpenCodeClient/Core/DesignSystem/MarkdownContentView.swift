import SwiftUI
import Textual

struct MarkdownContentView: View {
    let markdown: String

    var body: some View {
        StructuredText(markdown: markdown)
            .textual.structuredTextStyle(.gitHub)
            .textual.textSelection(.enabled)
            .font(.body)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
