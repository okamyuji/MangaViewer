import AppKit
import Foundation

actor ImageCacheActor {
    private var prefetchTasks: [Int: Task<Void, Never>] = [:]
    private var generation: Int = 0

    func currentGeneration() -> Int {
        generation
    }

    func incrementGeneration() {
        generation += 1
    }

    func cancelOutOfRangeTasks(currentIndex: Int, prefetchCount: Int) {
        for existingIndex in prefetchTasks.keys where abs(existingIndex - currentIndex) > prefetchCount {
            prefetchTasks[existingIndex]?.cancel()
            prefetchTasks.removeValue(forKey: existingIndex)
        }
    }

    func hasTask(for index: Int) -> Bool {
        prefetchTasks[index] != nil
    }

    func setTask(_ task: Task<Void, Never>, for index: Int) {
        prefetchTasks[index] = task
    }

    func removeTask(for index: Int) {
        prefetchTasks.removeValue(forKey: index)
    }

    func cancelAllTasks() {
        for task in prefetchTasks.values {
            task.cancel()
        }
        prefetchTasks.removeAll()
    }
}

final class ImageCache: @unchecked Sendable {
    private let cache = NSCache<NSNumber, NSImage>()
    private let prefetchCount = 3
    private let actor = ImageCacheActor()

    init() {
        cache.countLimit = 50
        cache.totalCostLimit = 500 * 1024 * 1024 // 500MB
    }

    func image(for index: Int) -> NSImage? {
        cache.object(forKey: NSNumber(value: index))
    }

    func set(_ image: NSImage, for index: Int) {
        let cost = Int(image.size.width * image.size.height * 4)
        cache.setObject(image, forKey: NSNumber(value: index), cost: cost)
    }

    func prefetch(around index: Int, totalPages: Int, using provider: PageProvider) {
        Task {
            let currentGen = await actor.currentGeneration()
            await actor.cancelOutOfRangeTasks(currentIndex: index, prefetchCount: prefetchCount)

            let indicesToPrefetch = prefetchIndices(around: index, totalPages: totalPages)

            for prefetchIndex in indicesToPrefetch {
                if cache.object(forKey: NSNumber(value: prefetchIndex)) != nil {
                    continue
                }
                if await actor.hasTask(for: prefetchIndex) {
                    continue
                }

                let task = Task { [weak self] in
                    guard let self else { return }
                    do {
                        let image = try await provider.image(at: prefetchIndex)
                        let gen = await self.actor.currentGeneration()
                        if !Task.isCancelled, gen == currentGen {
                            self.set(image, for: prefetchIndex)
                        }
                    } catch {
                        // Silently ignore prefetch errors
                    }

                    await self.actor.removeTask(for: prefetchIndex)
                }

                await actor.setTask(task, for: prefetchIndex)
            }
        }
    }

    private func prefetchIndices(around index: Int, totalPages: Int) -> [Int] {
        var indices: [Int] = []

        for offset in 1 ... prefetchCount {
            let nextIndex = index + offset
            if nextIndex < totalPages {
                indices.append(nextIndex)
            }
        }

        for offset in 1 ... prefetchCount {
            let prevIndex = index - offset
            if prevIndex >= 0 {
                indices.append(prevIndex)
            }
        }

        return indices
    }

    func clear() async {
        await actor.incrementGeneration()
        await actor.cancelAllTasks()
        cache.removeAllObjects()
    }
}
