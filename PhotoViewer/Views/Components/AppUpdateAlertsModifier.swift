import SwiftUI

struct AppUpdateAlertsModifier: ViewModifier {
  @Bindable var updates: AppUpdateModel
  @Environment(\.scenePhase) private var scenePhase

  func body(content: Content) -> some View {
    content
      .task {
        await updates.performCheckOnLaunch()
      }
      .onChange(of: scenePhase) { _, phase in
        guard phase == .active else { return }
        Task { await updates.performPeriodicCheckIfNeeded() }
      }
      .sheet(
        isPresented: Binding(
          get: { updates.offerToPresent != nil },
          set: { if !$0, updates.installPhase == .idle { updates.offerToPresent = nil } }
        )
      ) {
        if let offer = updates.offerToPresent {
          AppUpdateSheet(offer: offer, updates: updates)
        }
      }
      .alert(item: $updates.manualCheckAlert) { alert in
        Alert(
          title: Text(alert.title),
          message: Text(alert.message),
          dismissButton: .default(Text("OK"))
        )
      }
  }
}

extension View {
  func appUpdateAlerts(using updates: AppUpdateModel) -> some View {
    modifier(AppUpdateAlertsModifier(updates: updates))
  }
}