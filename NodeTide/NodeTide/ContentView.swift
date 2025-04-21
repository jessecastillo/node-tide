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

// MARK: - CanvasView

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
    @State private var cutMode: Bool = false
    @State private var selectedForConnection: [Int] = []
    @State private var connections: [(Int, Int)] = []
    @State private var liveDragOffsets: [Int: CGSize] = [:]
    @State private var connectionPulse: UUID = UUID()
    @State private var connectionDirections: [String: Bool] = [:]
    @State private var viewportHeight: CGFloat = 0
    @State private var glowingNode: Int? = nil
    @State private var temporaryGlow: Int? = nil

    var body: some View {
        GeometryReader { geo in
            ScrollView([.horizontal, .vertical]) {
                ZStack {
                    // Background
                    (colorScheme == .dark
                        ? Color(red: 0.12, green: 0.12, blue: 0.12)
                        : Color.white)

                    GridBackground()

                    ConnectionLayer(
                        positions: nodePositions,
                        connections: connections,
                        offsets: liveDragOffsets,
                        directions: connectionDirections,
                        pulseID: connectionPulse
                    )

                    NodeLayer(
                        nodePositions: $nodePositions,
                        nodeNames: $nodeNames,
                        snappingEnabled: snappingEnabled,
                        connectMode: connectMode,
                        selectedForConnection: $selectedForConnection,
                        connections: $connections,
                        dragOffsets: $liveDragOffsets,
                        glowingNode: glowingNode,
                        temporaryGlow: temporaryGlow,
                        undoStack: $undoStack,
                        redoStack: $redoStack
                    )
                }
                .coordinateSpace(name: "canvas")
                .gesture(cutGesture)
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
        .overlay(controlPanel, alignment: .top)
        .overlay(namePrompt)
    }

    // MARK: - Control Panel

    private var controlPanel: some View {
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
                Button("Cut") {
                    cutMode.toggle()
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(cutMode ? Color.red.opacity(0.2) : Color.clear)
                .cornerRadius(8)
                Toggle("Snap to Grid", isOn: $snappingEnabled)
                    .toggleStyle(SwitchToggleStyle())
            }
            .padding()
            .background(Color.gray.opacity(0.2))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .foregroundColor(colorScheme == .dark ? .white : .black)
            Spacer()
        }
        .padding()
    }

    // MARK: - Name Prompt

    @ViewBuilder
    private var namePrompt: some View {
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
                        .onSubmit { createNode() }
                    HStack(spacing: 20) {
                        Button("Create", action: createNode)
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
            .onExitCommand { showingNamePrompt = false }
        }
    }

    private func createNode() {
        let lastPos = nodePositions.last ?? CGPoint(x: 300, y: 300)
        let newPos = CGPoint(x: lastPos.x + 80, y: lastPos.y + 50)
        let finalName = newNodeName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "Node \(nodePositions.count + 1)"
            : newNodeName

        withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
            undoStack.append((nodePositions, nodeNames, connections))
            redoStack = []
            nodePositions.append(newPos)
            nodeNames.append(finalName)
        }
        showingNamePrompt = false
    }

    // MARK: - Cut Gesture

    private var cutGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onEnded { value in
                guard cutMode else { return }
                // Save undo state
                undoStack.append((nodePositions, nodeNames, connections))
                redoStack = []
                
                let tapPoint = value.location
                
                // Filter out any connections whose segment is within 10 pts of the tap
                connections = connections.filter { start, end in
                    let sOff = liveDragOffsets[start] ?? .zero
                    let eOff = liveDragOffsets[end] ?? .zero
                    let s = CGPoint(x: nodePositions[start].x + sOff.width,
                                    y: nodePositions[start].y + sOff.height)
                    let e = CGPoint(x: nodePositions[end].x + eOff.width,
                                    y: nodePositions[end].y + eOff.height)
                    let dist = distancePointToSegment(point: tapPoint, segmentStart: s, segmentEnd: e)
                    return dist > 10
                }
            }
    }
}

// MARK: - Subviews

struct GridBackground: View {
    var body: some View {
        Canvas { context, size in
            let spacing: CGFloat = 40
            let cols = Int(2000 / spacing)
            let rows = Int(2000 / spacing)

            for row in 0...rows {
                let y = CGFloat(row) * spacing
                context.stroke(Path { p in
                    p.move(to: .init(x: 0, y: y))
                    p.addLine(to: .init(x: 2000, y: y))
                }, with: .color(Color.gray.opacity(0.1)))
            }

            for col in 0...cols {
                let x = CGFloat(col) * spacing
                context.stroke(Path { p in
                    p.move(to: .init(x: x, y: 0))
                    p.addLine(to: .init(x: x, y: 2000))
                }, with: .color(Color.gray.opacity(0.1)))
            }
        }
    }
}

struct ConnectionLayer: View {
    let positions: [CGPoint]
    let connections: [(Int, Int)]
    let offsets: [Int: CGSize]
    let directions: [String: Bool]
    let pulseID: UUID

    var body: some View {
        Canvas { context, size in
            for (start, end) in connections {
                let sOff = offsets[start] ?? .zero
                let eOff = offsets[end] ?? .zero
                let s = CGPoint(x: positions[start].x + sOff.width,
                                y: positions[start].y + sOff.height)
                let e = CGPoint(x: positions[end].x + eOff.width,
                                y: positions[end].y + eOff.height)
                let mid = CGPoint(x: (s.x + e.x)/2, y: (s.y + e.y)/2)
                let key = "\(min(start,end))-\(max(start,end))"
                let dir = directions[key] ?? true
                let target = dir ? e : s

                var path = Path()
                path.move(to: s)
                path.addLine(to: e)
                context.stroke(path,
                               with: .color(Color.blue.opacity(0.5)),
                               style: StrokeStyle(lineWidth: 1.5, dash: [8,4]))
                context.fill(drawArrow(at: mid, toward: target),
                             with: .color(Color.blue.opacity(0.8)))
            }
        }
        .id(pulseID)
    }
}

struct NodeLayer: View {
    @Binding var nodePositions: [CGPoint]
    @Binding var nodeNames: [String]
    var snappingEnabled: Bool
    var connectMode: Bool
    @Binding var selectedForConnection: [Int]
    @Binding var connections: [(Int, Int)]
    @Binding var dragOffsets: [Int: CGSize]
    var glowingNode: Int?
    var temporaryGlow: Int?
    @Binding var undoStack: [([CGPoint], [String], [(Int,Int)])]
    @Binding var redoStack: [([CGPoint], [String], [(Int,Int)])]

    // MARK: - Node Tap Handler
    private func handleNodeTap(_ index: Int) {
        guard connectMode else { return }
        selectedForConnection.append(index)
        if selectedForConnection.count == 2 {
            undoStack.append((nodePositions, nodeNames, connections))
            redoStack = []
            let pair = (selectedForConnection[0], selectedForConnection[1])
            if !connections.contains(where: { $0 == pair || $0 == (pair.1, pair.0) }) {
                connections.append(pair)
            }
            selectedForConnection = []
        }
    }

    var body: some View {
        ForEach(nodePositions.indices, id: \.self) { index in
            if index < nodeNames.count {
                DraggableNode(
                    text: nodeNames[index],
                    position: $nodePositions[index],
                    snappingEnabled: snappingEnabled,
                    index: index,
                    dragOffsets: $dragOffsets,
                    glowState: glowingNode == index 
                               || temporaryGlow == index 
                               || (connectMode && selectedForConnection.contains(index))
                )
                .onTapGesture {
                    handleNodeTap(index)
                }
            }
        }
    }
}

// MARK: - DraggableNode

struct DraggableNode: View {
    let text: String
    @Binding var position: CGPoint
    var snappingEnabled: Bool
    var index: Int
    @Binding var dragOffsets: [Int: CGSize]
    var glowState: Bool
    @GestureState private var localDrag: CGSize = .zero

    private func snapToGrid(_ point: CGPoint, spacing: CGFloat = 40) -> CGPoint {
        CGPoint(x: round(point.x / spacing) * spacing,
                y: round(point.y / spacing) * spacing)
    }

    var body: some View {
        Text(text)
            .padding(.horizontal, 24)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.white.opacity(0.1))
                    .background(.ultraThinMaterial)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(
                        LinearGradient(
                            colors: [Color.white.opacity(0.5), Color.white.opacity(0.1)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1.2
                    )
            )
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .shadow(color: .black.opacity(0.1), radius: 16, x: 0, y: 8)
            .shadow(color: glowState ? .blue.opacity(0.4) : .clear, radius: 12, x: 0, y: 0)
            .foregroundColor(.white)
            .position(x: position.x + localDrag.width,
                      y: position.y + localDrag.height)
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
                        // Prevent dragging under the navbar (approx height 120)
                        position.y = max(position.y, 120)
                        dragOffsets[index] = .zero
                    }
            )
    }
}

// MARK: - Helpers

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

// MARK: - Geometry Helpers
private func distancePointToSegment(point p: CGPoint, segmentStart v: CGPoint, segmentEnd w: CGPoint) -> CGFloat {
    let l2 = pow(v.x - w.x, 2) + pow(v.y - w.y, 2)
    if l2 == 0 { return hypot(p.x - v.x, p.y - v.y) }
    var t = ((p.x - v.x) * (w.x - v.x) + (p.y - v.y) * (w.y - v.y)) / l2
    t = max(0, min(1, t))
    let proj = CGPoint(x: v.x + t * (w.x - v.x), y: v.y + t * (w.y - v.y))
    return hypot(p.x - proj.x, p.y - proj.y)
}

extension Notification.Name {
    static let undoCommand = Notification.Name("undoCommand")
    static let redoCommand = Notification.Name("redoCommand")
}

// MARK: - Preview

#Preview {
    ContentView()
}
