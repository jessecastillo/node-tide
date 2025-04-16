//
//  ContentView.swift
//  NodeTide
//
//  Created by Jesse Castillo on 4/14/25.
//

import SwiftUI
import AppKit

struct ContentView: View {
    var body: some View {
        CanvasView()
            .edgesIgnoringSafeArea(.all)
    }
}

struct CanvasView: View {
    @Environment(\.colorScheme) var colorScheme
    @State private var undoStack: [([CGPoint], [String], [(Int, Int)])] = []
    @State private var redoStack: [([CGPoint], [String], [(Int, Int)])] = []
    @State private var nodePositions: [CGPoint] = [CGPoint(x: 300, y: 300)]
    @State private var nodeNames: [String] = ["Node 1"]
    @State private var showingNamePrompt = false
    @State private var newNodeName = ""
    @FocusState private var isInputFocused: Bool
    @State private var snappingEnabled: Bool = false
    @State private var connectMode: Bool = false
    @State private var selectedForConnection: [Int] = []
    @State private var connections: [(Int, Int)] = []
    @State private var liveDragOffsets: [Int: CGSize] = [:]
    @State private var connectionPulse: UUID = UUID()
    @State private var connectionDirections: [String: Bool] = [:] // true = start to end, false = end to start
    @State private var viewportHeight: CGFloat = 0
    @State private var glowingNode: Int? = nil
    @State private var temporaryGlow: Int? = nil

    var body: some View {
        GeometryReader { geo in
            ScrollView([.horizontal, .vertical]) {
                ZStack {
                    // Background
                    (colorScheme == .dark ? Color(red: 0.12, green: 0.12, blue: 0.12) : Color.white)

                    // Gridlines
                    Canvas { context, size in
                        let spacing: CGFloat = 40
                        let columns = Int(2000 / spacing)
                        let rows = Int(2000 / spacing)

                        for row in 0...rows {
                            let y = CGFloat(row) * spacing
                            context.stroke(Path { path in
                                path.move(to: CGPoint(x: 0, y: y))
                                path.addLine(to: CGPoint(x: 2000, y: y))
                            }, with: .color(Color.gray.opacity(0.1)))
                        }

                        for col in 0...columns {
                            let x = CGFloat(col) * spacing
                            context.stroke(Path { path in
                                path.move(to: CGPoint(x: x, y: 0))
                                path.addLine(to: CGPoint(x: x, y: 2000))
                            }, with: .color(Color.gray.opacity(0.1)))
                        }
                        
                        for (startIdx, endIdx) in connections {
                            let startOffset = liveDragOffsets[startIdx] ?? .zero
                            let endOffset = liveDragOffsets[endIdx] ?? .zero
                            let start = CGPoint(x: nodePositions[startIdx].x + startOffset.width,
                                                y: nodePositions[startIdx].y + startOffset.height)
                            let end = CGPoint(x: nodePositions[endIdx].x + endOffset.width,
                                              y: nodePositions[endIdx].y + endOffset.height)

                            let midPoint = CGPoint(
                                x: (start.x + end.x) / 2,
                                y: (start.y + end.y) / 2
                            )

                            let keyValue = key(for: (startIdx, endIdx))
                            if connectionDirections[keyValue] == nil {
                                connectionDirections[keyValue] = true
                            }
                            let direction = connectionDirections[keyValue] ?? true
                            let arrowStart = direction ? midPoint : end
                            let arrowTarget = direction ? end : start

                            var linePath = Path()
                            linePath.move(to: start)
                            linePath.addLine(to: end)

                            context.stroke(linePath,
                                           with: .color(Color.blue.opacity(0.5)),
                                           style: StrokeStyle(lineWidth: 1.5, dash: [8, 4]))

                            context.fill(drawArrow(at: midPoint, toward: arrowTarget), with: .color(Color.blue.opacity(0.8)))
                        }
                    }
                    .frame(width: 2000, height: 2000)
                    .id(connectionPulse)
                    

                    // Example Nodes
                    ForEach(nodePositions.indices, id: \.self) { index in
                        if index < nodeNames.count {
                            DraggableNode(
                                text: nodeNames[index],
                                position: $nodePositions[index],
                                snappingEnabled: snappingEnabled,
                                index: index,
                                dragOffsets: $liveDragOffsets,
                                glowState: glowingNode == index || temporaryGlow == index
                            )
                            .onTapGesture {
                                if connectMode {
                                    selectedForConnection.append(index)

                                    if selectedForConnection.count == 1 {
                                        glowingNode = index
                                    }

                            if selectedForConnection.count == 2 {
                                undoStack.append((nodePositions, nodeNames, connections))
                                redoStack = []
                                let pair = (selectedForConnection[0], selectedForConnection[1])
                                if !connections.contains(where: { $0 == pair || $0 == (pair.1, pair.0) }) {
                                    connections.append(pair)
                                    connectionPulse = UUID()
                                    let keyValue = key(for: pair)
                                    if connectionDirections[keyValue] == nil {
                                        connectionDirections[keyValue] = true
                                    }
                                }

                                        let first = selectedForConnection[0]
                                        let second = selectedForConnection[1]
                                        temporaryGlow = second
                                        
                                        withAnimation(.easeOut(duration: 0.6)) {
                                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                                                if glowingNode == first {
                                                    glowingNode = nil
                                                }
                                                if temporaryGlow == second {
                                                    temporaryGlow = nil
                                                }
                                            }
                                        }
                                        selectedForConnection = []
                                    }
                                }
                            }
                        }
                    }
                }
                .frame(width: 2000, height: 2000)
                    .onAppear {
                        viewportHeight = geo.size.height
                    }
                    .onReceive(NotificationCenter.default.publisher(for: .undoCommand)) { _ in
                        if let last = undoStack.popLast() {
                            redoStack.append((nodePositions, nodeNames, connections))
                            nodePositions = last.0
                            nodeNames = last.1
                            connections = last.2
                        }
                    }
                    .onReceive(NotificationCenter.default.publisher(for: .redoCommand)) { _ in
                        if let redo = redoStack.popLast() {
                            undoStack.append((nodePositions, nodeNames, connections))
                            nodePositions = redo.0
                            nodeNames = redo.1
                            connections = redo.2
                        }
                    }
            }
        }
            .overlay(
            VStack {
                HStack {
                    Button("Add Node") {
                        newNodeName = ""
                        showingNamePrompt = true
                        isInputFocused = true
                    }
                    Button("Connect") {
                        connectMode.toggle()
                        selectedForConnection = []
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(connectMode ? Color.blue.opacity(0.2) : Color.clear)
                    .cornerRadius(8)
                    Button("Clear") { }
                    Toggle("Snap to Grid", isOn: $snappingEnabled)
                        .toggleStyle(SwitchToggleStyle())
                }
                .padding()
                .background(Color.gray.opacity(0.2))
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .foregroundColor(colorScheme == .dark ? .white : .black)
                Spacer()
            }
            .padding(),
            alignment: .top
        )
        .overlay(
            Group {
                if showingNamePrompt {
                    ZStack {
                        Color.black.opacity(0.4).ignoresSafeArea()
                        VStack(spacing: 16) {
                            Text("Name your node")
                                .foregroundColor(.white)
                                .font(.headline)
                            TextField("Enter name", text: $newNodeName)
                                .textFieldStyle(RoundedBorderTextFieldStyle())
                                .padding()
                                .frame(width: 240)
                                .focused($isInputFocused)
                                .onSubmit {
                                    let lastPosition = nodePositions.last ?? CGPoint(x: 300, y: 300)
                                    let newPosition = CGPoint(x: lastPosition.x + 80, y: lastPosition.y + 50)

                                    let finalName = newNodeName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                        ? "Node \(nodePositions.count + 1)"
                                        : newNodeName
                                    withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                                        undoStack.append((nodePositions, nodeNames, connections))
                                        redoStack = []
                                        nodePositions.append(newPosition)
                                        nodeNames.append(finalName)
                                    }
                                    showingNamePrompt = false
                                }
                            HStack(spacing: 20) {
                                Button("Create") {
                                    let lastPosition = nodePositions.last ?? CGPoint(x: 300, y: 300)
                                    let newPosition = CGPoint(x: lastPosition.x + 80, y: lastPosition.y + 50)
                                    
                                    let finalName = newNodeName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                        ? "Node \(nodePositions.count + 1)"
                                        : newNodeName
                                    withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                                        undoStack.append((nodePositions, nodeNames, connections))
                                        redoStack = []
                                        nodePositions.append(newPosition)
                                        nodeNames.append(finalName)
                                    }
                                    showingNamePrompt = false
                                }
                                
                                Button("Cancel") {
                                    showingNamePrompt = false
                                }
                                .foregroundColor(.red)
                            }
                            .padding(.top, 8)
                        }
                        .padding()
                        .background(Color(nsColor: NSColor.controlBackgroundColor))
                        .cornerRadius(12)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                    .onExitCommand {
                        showingNamePrompt = false
                    }
                }
            }
        )
    }
    
    func key(for pair: (Int, Int)) -> String {
        "\(min(pair.0, pair.1))-\(max(pair.0, pair.1))"
    }
    
    func drawArrow(at point: CGPoint, toward target: CGPoint) -> Path {
        let arrowSize: CGFloat = 10
        let dx = target.x - point.x
        let dy = target.y - point.y
        let angle = atan2(dy, dx)
        
        var path = Path()
        path.move(to: CGPoint(x: point.x + cos(angle) * arrowSize,
                              y: point.y + sin(angle) * arrowSize))
        path.addLine(to: CGPoint(x: point.x + cos(angle + .pi * 0.75) * arrowSize * 0.6,
                                 y: point.y + sin(angle + .pi * 0.75) * arrowSize * 0.6))
        path.addLine(to: CGPoint(x: point.x + cos(angle - .pi * 0.75) * arrowSize * 0.6,
                                 y: point.y + sin(angle - .pi * 0.75) * arrowSize * 0.6))
        path.closeSubpath()
        return path
    }
}

struct DraggableNode: View {
    let text: String
    @Binding var position: CGPoint
    var snappingEnabled: Bool
    var index: Int
    @Binding var dragOffsets: [Int: CGSize]
    var glowState: Bool
    @GestureState private var localDrag: CGSize = .zero

    private func snapToGrid(_ point: CGPoint, spacing: CGFloat = 40) -> CGPoint {
        CGPoint(
            x: round(point.x / spacing) * spacing,
            y: round(point.y / spacing) * spacing
        )
    }

    var body: some View {
        Text(text)
            .padding(.horizontal, 24)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(
                        Color.white.opacity(0.1)
                            .blendMode(.plusLighter)
                    )
                    .background(.ultraThinMaterial)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [Color.white.opacity(0.5), Color.white.opacity(0.1)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1.2
                    )
            )
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .shadow(color: Color.black.opacity(0.1), radius: 16, x: 0, y: 8)
            .shadow(color: glowState ? Color.blue.opacity(0.4) : Color.clear, radius: 12, x: 0, y: 0)
            .foregroundColor(.white)
            .position(x: position.x + localDrag.width, y: position.y + localDrag.height)
            .gesture(
                DragGesture()
                    .updating($localDrag) { value, state, _ in
                        state = value.translation
                        DispatchQueue.main.async {
                            dragOffsets[index] = value.translation
                        }
                    }
                    .onEnded { value in
                        position.x += value.translation.width
                        position.y += value.translation.height
                        dragOffsets[index] = .zero
                    }
            )
    }
}

#Preview {
    ContentView()
}

extension Notification.Name {
    static let undoCommand = Notification.Name("undoCommand")
    static let redoCommand = Notification.Name("redoCommand")
}
