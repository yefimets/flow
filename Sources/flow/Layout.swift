import CoreGraphics

/// One column of the grid: one or two windows, top to bottom.
final class Column {
    var windows: [Window]
    /// Share of the column's height given to the upper window when there are two.
    var rowRatio: CGFloat = 0.5
    /// The index this column had when its windows were last laid out. Windows coming back after a
    /// Space switch or a restart ask for their old column by this number, in any arrival order.
    var origin: Int

    init(_ window: Window, origin: Int = 0) {
        windows = [window]
        self.origin = origin
    }

    var minWidth: CGFloat { windows.map { $0.minSize.width }.max() ?? 0 }
}

/// A fixed grid per display: at most two columns, at most two rows per column.
/// Widths follow `columnRatio`, each column's rows follow its `rowRatio`, and both bend to the
/// windows' minimum sizes. A window whose minimum height cannot share a column is evicted rather than clipped.
final class Grid {
    static let maxColumns = 2
    static let maxRows = 2

    private(set) var columns: [Column] = []
    /// Share of the width given to the left column when there are two.
    var columnRatio: CGFloat = 0.5

    var isEmpty: Bool { columns.isEmpty }
    var windows: [Window] { columns.flatMap(\.windows) }
    var hasRoom: Bool { columns.count < Self.maxColumns || columns.contains { $0.windows.count < Self.maxRows } }

    func position(of w: Window) -> (column: Int, row: Int)? {
        for (ci, c) in columns.enumerated() {
            if let ri = c.windows.firstIndex(where: { $0 === w }) { return (ci, ri) }
        }
        return nil
    }

    func contains(_ w: Window) -> Bool { position(of: w) != nil }

    /// Places a window: side by side while there is a free column, then under the anchor,
    /// then in whichever column has a free row. With `strict`, a row is only used when both
    /// minimum heights fit the column, so nothing will be evicted afterwards. False when nothing suits.
    @discardableResult
    func insert(_ w: Window, near anchor: Window?, area: CGRect = .infinite, gap: CGFloat = 0, strict: Bool = false,
                preferredColumn: Int? = nil, preferredRow: Int? = nil) -> Bool {
        // A window coming back (after a lock, a Space switch, a minimise) asks for its old slot.
        if let ci = preferredColumn {
            // Two windows always sit side by side. Stacking them under one remembered column only
            // happens when the window that used to hold the other column is gone; do not honour that.
            if columns.count == 1, columns[0].windows.count == 1 {
                let side = ci < columns[0].origin ? 0 : 1
                let origin = ci == columns[0].origin ? ci + 1 : ci
                columns.insert(Column(w, origin: origin), at: side)
                return true
            }
            if let c = columns.first(where: { $0.origin == ci }), c.windows.count < Self.maxRows {
                c.windows.insert(w, at: preferredRow == 0 ? 0 : c.windows.count)
                return true
            }
            if !columns.contains(where: { $0.origin == ci }), columns.count < Self.maxColumns {
                let at = columns.filter { $0.origin < ci }.count
                columns.insert(Column(w, origin: ci), at: at)
                return true
            }
        }
        if columns.count < Self.maxColumns {
            columns.append(Column(w, origin: columns.count))
            renumber()
            return true
        }
        let preferred = anchor.flatMap { position(of: $0)?.column } ?? columns.count - 1
        let order = [preferred] + columns.indices.filter { $0 != preferred }
        for ci in order where columns[ci].windows.count < Self.maxRows {
            let fits = columns[ci].windows[0].minSize.height + gap + w.minSize.height <= area.height
            if strict, !fits { continue }
            columns[ci].windows.append(w)
            return true
        }
        return false
    }

    func remove(_ w: Window) {
        guard let p = position(of: w) else { return }
        columns[p.column].windows.remove(at: p.row)
        if columns[p.column].windows.isEmpty { columns.remove(at: p.column) }
        spreadPair()
    }

    /// Two windows left stacked in the only column spread into two columns: the upper one goes left.
    private func spreadPair() {
        guard columns.count == 1, columns[0].windows.count == 2 else { return }
        let lower = columns[0].windows.removeLast()
        columns.append(Column(lower, origin: 1))
        columns[0].origin = 0
    }

    /// Makes each column's origin its current index. Called after deliberate rearrangements.
    private func renumber() {
        for (i, c) in columns.enumerated() { c.origin = i }
    }

    func swap(_ a: Window, _ b: Window) {
        guard let pa = position(of: a), let pb = position(of: b) else { return }
        columns[pa.column].windows[pa.row] = b
        columns[pb.column].windows[pb.row] = a
    }

    /// Exchanges the two columns as whole units. Rows keep their order; the widths travel with the columns.
    func swapColumns() {
        guard columns.count == 2 else { return }
        columns.reverse()
        columnRatio = 1 - columnRatio
        renumber()
    }

    /// Breaks a window out of a shared column into a new column on the given side.
    /// False when the window is already alone in its column or both columns exist.
    @discardableResult
    func moveToNewColumn(_ w: Window, side: Direction) -> Bool {
        guard columns.count < Self.maxColumns, let p = position(of: w),
              columns[p.column].windows.count > 1 else { return false }
        remove(w)
        if side == .left { columns.insert(Column(w), at: 0) } else { columns.append(Column(w)) }
        renumber()
        return true
    }

    /// Moves a window out of its column into the other one, or into a new column. False when there is no room.
    @discardableResult
    func moveToOtherColumn(_ w: Window) -> Bool {
        guard let p = position(of: w) else { return false }
        if columns.count < Self.maxColumns {
            guard columns[p.column].windows.count > 1 else { return false }
            remove(w)
            columns.append(Column(w))
            renumber()
            return true
        }
        guard let other = columns.indices.first(where: { $0 != p.column && columns[$0].windows.count < Self.maxRows })
        else { return false }
        columns[other].windows.append(w)
        columns[p.column].windows.remove(at: p.row)
        if columns[p.column].windows.isEmpty { columns.remove(at: p.column) }
        renumber()
        return true
    }

    /// The tile the user placed least recently. Parked when an explicit placement needs its slot.
    func lowestPriority(excluding w: Window? = nil) -> Window? {
        windows.filter { $0 !== w }.min { $0.priority < $1.priority }
    }

    /// Frames for every window, and the windows evicted because two minimum heights could not share a column.
    /// The window placed least recently is the one evicted; on a tie the lower one goes.
    func layout(in area: CGRect, gap: CGFloat) -> (frames: [(Window, CGRect)], evicted: [Window]) {
        var frames: [(Window, CGRect)] = []
        var evicted: [Window] = []
        guard !columns.isEmpty else { return (frames, evicted) }

        for c in columns where c.windows.count == 2 {
            let upper = c.windows[0], lower = c.windows[1]
            if upper.minSize.height + gap + lower.minSize.height > area.height {
                let victim = upper.priority < lower.priority ? upper : lower
                evicted.append(victim)
                c.windows.removeAll { $0 === victim }
            }
        }

        let widths = columnWidths(total: area.width, gap: gap)
        var x = area.minX
        for (ci, c) in columns.enumerated() {
            let width = widths[ci]
            if c.windows.count == 1 {
                frames.append((c.windows[0], CGRect(x: x, y: area.minY, width: width, height: area.height)))
            } else {
                let usable = area.height - gap
                let minA = c.windows[0].minSize.height, minB = c.windows[1].minSize.height
                var h1 = (usable * c.rowRatio).rounded()
                h1 = min(max(h1, minA), usable - minB)
                frames.append((c.windows[0], CGRect(x: x, y: area.minY, width: width, height: h1)))
                frames.append((c.windows[1], CGRect(x: x, y: area.minY + h1 + gap, width: width, height: usable - h1)))
            }
            x += width + gap
        }
        return (frames, evicted)
    }

    private func columnWidths(total: CGFloat, gap: CGFloat) -> [CGFloat] {
        if columns.count == 1 { return [total] }
        let usable = total - gap
        let minA = columns[0].minWidth, minB = columns[1].minWidth
        var w1 = (usable * columnRatio).rounded()
        if usable >= minA + minB {
            w1 = min(max(w1, minA), usable - minB)
        } else if minA + minB > 0 {
            w1 = (usable * minA / (minA + minB)).rounded()
        }
        return [w1, usable - w1]
    }
}
