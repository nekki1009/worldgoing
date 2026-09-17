using Godot;
using System;
using System.Collections.Generic;

// Call-local broad phase only. No people, HP, clocks, Nodes, terrain or RNG.
// Return original ordinals, keeping the full roster's rotating priority.
public partial class compiled_exchange_candidates : RefCounted
{
    public int[] FrontOrder(int[] x, int[] y, long[] factions, long round)
    {
        if (x.Length != y.Length || x.Length != factions.Length || round < 0)
            throw new ArgumentException("Mismatched exchange columns or negative round");
        int count = x.Length;
        if (count == 0) return Array.Empty<int>();
        var occupied = new Dictionary<(long, long), long>(count);
        // Multiple factions may share a cell (e.g. independently controlled actors).
        var mixed = new HashSet<(long, long)>();
        for (int i = 0; i < count; i++)
        {
            var cell = ((long)x[i], (long)y[i]);
            if (occupied.TryGetValue(cell, out long faction))
            {
                if (faction != factions[i]) mixed.Add(cell);
            }
            else occupied.Add(cell, factions[i]);
        }
        var result = new List<int>();
        int start = (int)(round % count);
        for (int offset = 0; offset < count; offset++)
        {
            int i = (int)(((long)offset + start) % count);
            long cx = x[i], cy = y[i];
            if (Enemy((cx, cy - 1), factions[i]) || Enemy((cx + 1, cy), factions[i]) ||
                Enemy((cx, cy + 1), factions[i]) || Enemy((cx - 1, cy), factions[i]))
                result.Add(i);
        }
        return result.ToArray();

        bool Enemy((long, long) cell, long faction) =>
            occupied.TryGetValue(cell, out long other) && (other != faction || mixed.Contains(cell));
    }
}
