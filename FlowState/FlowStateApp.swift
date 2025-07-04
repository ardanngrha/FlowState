import SwiftUI
import AppKit
import Combine // Import Combine to listen for ViewModel changes

// MARK: - Main App Entry Point
@main
struct PomodoroApp: App {
    // Using AppDelegate to manage the popover and menu bar item
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // Settings scene is required for a MenuBarExtra app to function correctly.
        Settings {
            EmptyView()
        }
    }
}

// MARK: - AppDelegate for Managing App Lifecycle and UI
class AppDelegate: NSObject, NSApplicationDelegate {
    
    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    
    // Create a single instance of the ViewModel to be shared.
    private var viewModel = PomodoroViewModel()
    // Store Combine subscriptions
    private var cancellables = Set<AnyCancellable>()
    
    /// Called when the application has finished launching.
    @MainActor func applicationDidFinishLaunching(_ notification: Notification) {
        
        // 1. Create the Status Bar Item
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "timer", accessibilityDescription: "Pomodoro Timer")
            // --- EDIT: Set the image position to the right of the title ---
            button.imagePosition = .imageRight
            button.action = #selector(togglePopover)
            button.target = self
        }
        
        // 2. Create the Popover
        popover = NSPopover()
        // Pass the shared ViewModel into the SwiftUI view.
        popover.contentViewController = NSHostingController(rootView: PomodoroView(viewModel: viewModel))
        popover.behavior = .transient
        popover.animates = true
        
        // 3. Subscribe to ViewModel Changes to Update Menu Bar
        // This is the logic to show the timer in the menu bar.
        viewModel.$timerIsActive
            .combineLatest(viewModel.$timeString)
            // We want updates on the main thread to change the UI.
            .receive(on: DispatchQueue.main)
            .sink { [weak self] (isActive, timeString) in
                if isActive {
                    // If the timer is running, show the time in the menu bar.
                    // The title now appears to the left of the icon.
                    self?.statusItem.button?.title = timeString
                } else {
                    // If the timer is not running, clear the text to show only the icon.
                    self?.statusItem.button?.title = ""
                }
            }
            .store(in: &cancellables)
    }
    
    /// Toggles the visibility of the popover.
    @objc private func togglePopover() {
        if let button = statusItem.button {
            if popover.isShown {
                popover.performClose(nil)
            } else {
                popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
                NSApp.activate(ignoringOtherApps: true)
            }
        }
    }
}


// MARK: - Pomodoro Timer Logic (ViewModel)
class PomodoroViewModel: ObservableObject {
    
    // --- Published Properties ---
    @Published var taskName: String = ""
    @Published var timeRemaining: TimeInterval = 25 * 60
    @Published var timerIsActive: Bool = false
    
    // Make timeString a published property so AppDelegate can subscribe to it.
    @Published var timeString: String = "25:00"
    
    private var timer: Timer?
    
    init() {
        // Update the timeString whenever timeRemaining changes.
        $timeRemaining
            .map { remaining in
                let minutes = Int(remaining) / 60
                let seconds = Int(remaining) % 60
                return String(format: "%02d:%02d", minutes, seconds)
            }
            .assign(to: &$timeString)
    }
    
    // --- Timer Controls ---
    func startTimer() {
        guard !timerIsActive else { return }
        timerIsActive = true
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            
            if self.timeRemaining > 0 {
                self.timeRemaining -= 1
            } else {
                // When the timer finishes, stop it, send a notification, and reset.
                self.pauseTimer() // Stops the timer
                self.sendNotification()
                self.timeRemaining = 25 * 60 // Reset for the next session
            }
        }
    }
    
    func pauseTimer() {
        timerIsActive = false
        timer?.invalidate()
        timer = nil
    }
    
    func resetTimer() {
        pauseTimer()
        timeRemaining = 25 * 60
    }
    
    /// **NEW: Sends a user notification when the timer completes.**
    /// Uses the deprecated NSUserNotificationCenter for simplicity and broad compatibility,
    /// as it doesn't require explicit user permission for basic notifications.
    private func sendNotification() {
        let notification = NSUserNotification()
        notification.title = "Pomodoro Finished!"
        
        // Customize the notification text based on whether a task name was entered.
        let task = taskName.trimmingCharacters(in: .whitespaces).isEmpty ? "Your task" : "'\(taskName)'"
        notification.informativeText = "\(task) is complete. Time for a break!"
        notification.soundName = NSUserNotificationDefaultSoundName
        
        NSUserNotificationCenter.default.deliver(notification)
    }
}


// MARK: - The Main SwiftUI View
struct PomodoroView: View {
    
    // The view now uses an @ObservedObject, as the ViewModel is created and passed in by the AppDelegate.
    @ObservedObject var viewModel: PomodoroViewModel
    
    var body: some View {
        VStack(spacing: 15) {
            
            // --- EDIT: Headline is set to "FlowState" ---
            Text("FlowState")
                .font(.headline)
            
            TextField("Name your task...", text: $viewModel.taskName)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .padding(.horizontal)
            
            Text(viewModel.timeString)
                .font(.system(size: 60, weight: .bold, design: .monospaced))
                .foregroundColor(viewModel.timerIsActive ? .primary : .secondary)
            
            HStack(spacing: 20) {
                Button(action: {
                    if viewModel.timerIsActive {
                        viewModel.pauseTimer()
                    } else {
                        viewModel.startTimer()
                    }
                }) {
                    Image(systemName: viewModel.timerIsActive ? "pause.fill" : "play.fill")
                        .font(.title)
                }
                .buttonStyle(PlainButtonStyle())
                
                Button(action: viewModel.resetTimer) {
                    Image(systemName: "arrow.clockwise")
                        .font(.title)
                }
                .buttonStyle(PlainButtonStyle())
                .disabled(viewModel.timerIsActive)
            }
            
            Divider()
            
            Button("Quit App") {
                NSApplication.shared.terminate(nil)
            }
            .buttonStyle(PlainButtonStyle())
            .foregroundColor(.secondary)
            
        }
        .padding()
        .frame(width: 280)
    }
}
