//
//  SessionList.swift
//  FaleAgro LiDAR
//

import CoreData
import SwiftUI

class SessionListViewModel: ObservableObject {
    private var dataContext: NSManagedObjectContext?
    @Published var sessions: [Recording] = []

    init() {
        guard let appDelegate = UIApplication.shared.delegate as? AppDelegate else { return }
        dataContext = appDelegate.persistentContainer.viewContext
        NotificationCenter.default.addObserver(self, selector: #selector(sessionsChanged), name: NSNotification.Name("sessionsChanged"), object: nil)
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    func fetchSessions() {
        let request = NSFetchRequest<NSManagedObject>(entityName: "Recording")
        request.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: false)]
        do {
            let fetched = try dataContext?.fetch(request) ?? []
            sessions = fetched.compactMap { $0 as? Recording }
        } catch {
            print("Could not fetch sessions. \(error.localizedDescription)")
        }
    }

    @objc func sessionsChanged() {
        fetchSessions()
    }
}

struct SessionList: View {
    @ObservedObject var viewModel = SessionListViewModel()
    @State private var showingInfo = false

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("FaleAgro LiDAR")
                            .font(.largeTitle.weight(.bold))
                            .foregroundColor(Color("TextColor"))
                        Text("Estrutura do dossel · protótipo 1")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Button(action: { showingInfo = true }) {
                        Image(systemName: "info.circle")
                            .font(.title2)
                            .foregroundColor(Color("TextColor"))
                    }
                    .padding(.top, 8)
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 8)

                if viewModel.sessions.isEmpty {
                    Spacer()
                    Text("Nenhuma medição ainda.\nToque em Nova medição, preencha a ficha e grave no talhão.")
                        .font(.body)
                        .multilineTextAlignment(.center)
                        .foregroundColor(Color("TextColor"))
                        .padding(.horizontal, 32)
                    Spacer()
                } else {
                    List {
                        ForEach(viewModel.sessions) { recording in
                            NavigationLink(destination: SessionDetailView(recording: recording)) {
                                SessionRow(session: recording)
                            }
                            .listRowBackground(Color("BackgroundColor"))
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                }

                NavigationLink(destination: NewSessionView()) {
                    Text("Nova medição")
                        .font(.title3.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(Color(red: 0.12, green: 0.38, blue: 0.18))
                        .foregroundColor(.white)
                        .cornerRadius(18)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                }
            }
            .background(Color("BackgroundColor").ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $showingInfo) {
                InformationView()
            }
            .onAppear {
                viewModel.fetchSessions()
                let delegate = UIApplication.shared.delegate as? AppDelegate
                delegate?.appDaemon?.removeDeletedEntries()
            }
        }
        .environment(\.locale, Locale(identifier: "pt_BR"))
    }
}
