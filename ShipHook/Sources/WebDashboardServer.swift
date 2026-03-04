import Foundation
import Swifter

struct WebDashboardSnapshot: Codable {
    var generatedAt: Date
    var repositories: [Repository]

    struct Repository: Codable {
        var id: String
        var name: String
        var isEnabled: Bool
        var slug: String
        var branch: String
        var activity: String
        var phase: String
        var summary: String
        var version: String?
        var publishedVersion: String?
        var lastSeenSHA: String?
        var lastBuiltSHA: String?
        var lastCheckDate: Date?
        var lastSuccessDate: Date?
        var buildStartedAt: Date?
        var latestBuild: Build?
        var recentBuilds: [Build]
        var recentLog: String
        var lastLogPath: String?
        var lastError: String?
        var progress: Progress?
    }

    struct Build: Codable {
        var version: String
        var sha: String
        var builtAt: Date
    }

    struct Progress: Codable {
        var currentStep: Int
        var totalSteps: Int
        var label: String
        var fractionComplete: Double
    }
}

final class WebDashboardServer {
    enum Status: Equatable {
        case stopped
        case running(url: String)
        case failed(message: String)

        var message: String {
            switch self {
            case .stopped:
                return "Local web dashboard is turned off."
            case let .running(url):
                return "Local web dashboard is available at \(url)"
            case let .failed(message):
                return message
            }
        }

        var urlString: String? {
            switch self {
            case let .running(url):
                return url
            case .stopped, .failed:
                return nil
            }
        }
    }

    private let snapshotProvider: @MainActor () -> WebDashboardSnapshot
    private let server = HttpServer()
    private var isConfigured = false
    private var currentPort: in_port_t?
    private var status: Status = .stopped

    init(snapshotProvider: @escaping @MainActor () -> WebDashboardSnapshot) {
        self.snapshotProvider = snapshotProvider
    }

    func configure(enabled: Bool, port: Int) -> Status {
        stop()

        guard enabled else {
            status = .stopped
            return status
        }

        guard (1024...65535).contains(port) else {
            status = .failed(message: "Web dashboard port must be between 1024 and 65535.")
            return status
        }

        configureRoutesIfNeeded()

        let resolvedPort = in_port_t(clamping: port)
        do {
            try server.start(resolvedPort, forceIPv4: true)
            currentPort = resolvedPort
            status = .running(url: "http://127.0.0.1:\(resolvedPort)")
        } catch {
            currentPort = nil
            status = .failed(message: "Web dashboard failed to start: \(error.localizedDescription)")
        }

        return status
    }

    func currentStatus() -> Status {
        status
    }

    func stop() {
        server.stop()
        currentPort = nil
    }

    private func configureRoutesIfNeeded() {
        guard !isConfigured else {
            return
        }
        isConfigured = true

        server["/api/state"] = { [weak self] _ in
            guard let self else {
                return .internalServerError
            }
            return self.jsonResponse(for: self.currentSnapshot())
        }

        server["/"] = { [weak self] _ in
            guard let self else {
                return .internalServerError
            }
            return .ok(.html(self.htmlDocument(for: self.currentSnapshot())))
        }
    }

    private func currentSnapshot() -> WebDashboardSnapshot {
        DispatchQueue.main.sync {
            MainActor.assumeIsolated {
                snapshotProvider()
            }
        }
    }

    private func jsonResponse(for snapshot: WebDashboardSnapshot) -> HttpResponse {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        do {
            let data = try encoder.encode(snapshot)
            return .ok(.data(data, contentType: "application/json; charset=utf-8"))
        } catch {
            return .internalServerError
        }
    }

    private func htmlDocument(for _: WebDashboardSnapshot) -> String {
        Self.htmlTemplate
    }

    private static let htmlTemplate = """
<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>ShipHook Dashboard</title>
  <style>
    :root {
      color-scheme: light dark;
      --bg: radial-gradient(circle at top, rgba(28,187,255,.18), transparent 40%), linear-gradient(180deg, #0f1722 0%, #0b1119 100%);
      --card: rgba(255,255,255,.08);
      --border: rgba(255,255,255,.16);
      --text: rgba(255,255,255,.92);
      --muted: rgba(255,255,255,.62);
      --green: #38d39f;
      --amber: #ffbf47;
      --red: #ff6f7d;
      --blue: #77d3ff;
    }
    * { box-sizing: border-box; }
    body {
      margin: 0;
      min-height: 100vh;
      font: 14px/1.45 -apple-system, BlinkMacSystemFont, "SF Pro Text", sans-serif;
      background: var(--bg);
      color: var(--text);
    }
    .wrap { max-width: 1320px; margin: 0 auto; padding: 28px; }
    .hero {
      display: flex; justify-content: space-between; align-items: end; gap: 16px;
      margin-bottom: 24px;
    }
    .hero h1 { margin: 0; font-size: 30px; letter-spacing: -.03em; }
    .hero p { margin: 6px 0 0; color: var(--muted); }
    .badge {
      padding: 8px 12px; border-radius: 999px; border: 1px solid var(--border);
      background: rgba(255,255,255,.08); color: var(--muted);
      backdrop-filter: blur(24px) saturate(160%);
      -webkit-backdrop-filter: blur(24px) saturate(160%);
    }
    .grid {
      display: grid;
      grid-template-columns: repeat(auto-fit, minmax(320px, 1fr));
      gap: 18px;
    }
    .card {
      border-radius: 24px;
      padding: 18px;
      background: var(--card);
      border: 1px solid var(--border);
      backdrop-filter: blur(24px) saturate(160%);
      -webkit-backdrop-filter: blur(24px) saturate(160%);
      box-shadow: 0 16px 40px rgba(0,0,0,.22);
    }
    .topline, .meta, .versions, .history-item {
      display: flex; justify-content: space-between; gap: 12px; align-items: center;
    }
    .title {
      font-size: 20px; font-weight: 700; letter-spacing: -.03em; margin: 0;
    }
    .slug { color: var(--muted); font-size: 13px; }
    .status {
      display: inline-flex; align-items: center; gap: 8px;
      padding: 7px 11px; border-radius: 999px; font-size: 12px; font-weight: 700;
      border: 1px solid rgba(255,255,255,.16);
    }
    .dot { width: 9px; height: 9px; border-radius: 999px; }
    .status.idle, .status.succeeded { background: rgba(56,211,159,.12); color: var(--green); }
    .status.polling, .status.building { background: rgba(119,211,255,.12); color: var(--blue); }
    .status.failed { background: rgba(255,111,125,.14); color: var(--red); }
    .status.queued { background: rgba(255,191,71,.12); color: var(--amber); }
    .status.disabled { background: rgba(255,191,71,.16); color: var(--amber); }
    .summary { margin: 14px 0 16px; color: var(--text); min-height: 40px; }
    .meta { color: var(--muted); font-size: 12px; margin-bottom: 8px; }
    .versions {
      padding: 12px 14px; border-radius: 18px; background: rgba(255,255,255,.05); margin-bottom: 14px;
    }
    .versions strong { display: block; font-size: 12px; color: var(--muted); font-weight: 600; margin-bottom: 2px; }
    .versions span { font-size: 16px; font-weight: 700; }
    .progress-wrap { margin: 14px 0; }
    .progress-label { display:flex; justify-content:space-between; font-size:12px; color: var(--muted); margin-bottom: 8px; }
    .progress {
      height: 8px; border-radius: 999px; background: rgba(255,255,255,.08); overflow: hidden;
    }
    .bar { height: 100%; border-radius: inherit; background: linear-gradient(90deg, #78d5ff, #38d39f); }
    .history { margin-top: 14px; display: grid; gap: 8px; }
    .history-item {
      padding: 10px 12px; border-radius: 14px; background: rgba(255,255,255,.04); font-size: 12px;
    }
    pre {
      margin: 14px 0 0; padding: 12px; border-radius: 16px;
      background: rgba(3,8,13,.5); color: rgba(255,255,255,.84);
      font: 12px/1.45 ui-monospace, SFMono-Regular, Menlo, monospace;
      max-height: 180px; overflow: auto; white-space: pre-wrap;
    }
    .empty { color: var(--muted); font-size: 13px; }
    @media (max-width: 700px) {
      .wrap { padding: 18px; }
      .hero { flex-direction: column; align-items: start; }
    }
  </style>
</head>
<body>
  <div class="wrap">
    <div class="hero">
      <div>
        <h1>ShipHook Dashboard</h1>
        <p>Read-only local status for repositories, versions, logs, and recent builds.</p>
      </div>
      <div class="badge" id="updatedAt">Waiting for first refresh</div>
    </div>
    <div class="grid" id="repoGrid"></div>
  </div>
  <script>
    function escapeHtml(value) {
      return String(value == null ? "" : value)
        .replace(/&/g, "&amp;")
        .replace(/</g, "&lt;")
        .replace(/>/g, "&gt;")
        .replace(/"/g, "&quot;");
    }

    function formatDate(value) {
      if (!value) return "Never";
      var date = new Date(value);
      return Number.isNaN(date.getTime()) ? "Never" : date.toLocaleString();
    }

    function shortSHA(value) {
      return value ? value.slice(0, 7) : "None";
    }

    function statusClass(repo) {
      if (repo.isEnabled === false) return "disabled";
      if (repo.phase === "queued") return "queued";
      if (repo.activity === "failed") return "failed";
      if (repo.activity === "building" || repo.activity === "polling") return repo.activity;
      if (repo.activity === "succeeded") return "succeeded";
      return "idle";
    }

    function renderRepository(repo) {
      var progress = "";
      if (repo.progress) {
        var progressWidth = Math.max(0, Math.min(100, repo.progress.fractionComplete * 100));
        progress =
          '<div class="progress-wrap">' +
            '<div class="progress-label">' +
              '<span>Step ' + repo.progress.currentStep + ' of ' + repo.progress.totalSteps + '</span>' +
              '<span>' + escapeHtml(repo.progress.label) + '</span>' +
            '</div>' +
            '<div class="progress">' +
              '<div class="bar" style="width:' + progressWidth + '%"></div>' +
            '</div>' +
          '</div>';
      }

      var history = '<div class="empty">No ShipHook build history yet.</div>';
      if (repo.recentBuilds && repo.recentBuilds.length) {
        var historyItems = "";
        for (var i = 0; i < repo.recentBuilds.length; i += 1) {
          var build = repo.recentBuilds[i];
          historyItems +=
            '<div class="history-item">' +
              '<span>' + escapeHtml(build.version || "Unknown version") + '</span>' +
              '<span>' + shortSHA(build.sha) + ' · ' + formatDate(build.builtAt) + '</span>' +
            '</div>';
        }
        history = '<div class="history">' + historyItems + '</div>';
      }

      var statusText = repo.isEnabled === false ? "disabled" : (repo.phase === "queued" ? "Queued" : repo.activity);
      var logBlock = repo.recentLog ? '<pre>' + escapeHtml(repo.recentLog) + '</pre>' : "";

      return (
        '<section class="card">' +
          '<div class="topline">' +
            '<div>' +
              '<h2 class="title">' + escapeHtml(repo.name) + '</h2>' +
              '<div class="slug">' + escapeHtml(repo.slug) + ' · ' + escapeHtml(repo.branch) + '</div>' +
            '</div>' +
            '<div class="status ' + statusClass(repo) + '">' +
              '<span class="dot" style="background: currentColor"></span>' +
              '<span>' + escapeHtml(statusText) + '</span>' +
            '</div>' +
          '</div>' +
          '<p class="summary">' + escapeHtml(repo.summary) + '</p>' +
          '<div class="versions">' +
            '<div>' +
              '<strong>Current Version</strong>' +
              '<span>' + escapeHtml(repo.version || "Unknown") + '</span>' +
            '</div>' +
            '<div>' +
              '<strong>Published</strong>' +
              '<span>' + escapeHtml(repo.publishedVersion || "Unknown") + '</span>' +
            '</div>' +
          '</div>' +
          progress +
          '<div class="meta"><span>Latest Seen</span><span>' + shortSHA(repo.lastSeenSHA) + ' · ' + formatDate(repo.lastCheckDate) + '</span></div>' +
          '<div class="meta"><span>Latest Built</span><span>' + shortSHA(repo.lastBuiltSHA) + ' · ' + formatDate(repo.lastSuccessDate) + '</span></div>' +
          '<div class="history">' + history + '</div>' +
          logBlock +
        '</section>'
      );
    }

    function render(state) {
      document.getElementById("updatedAt").textContent = "Updated " + formatDate(state.generatedAt);
      document.getElementById("repoGrid").innerHTML = state.repositories.length
        ? state.repositories.map(renderRepository).join("")
        : '<section class="card"><div class="empty">No repositories configured yet.</div></section>';
    }

    function renderUnavailable(message) {
      document.getElementById("updatedAt").textContent = escapeHtml(message);
      document.getElementById("repoGrid").innerHTML =
        '<section class="card"><div class="empty">' + escapeHtml(message) + '</div></section>';
    }

    function refresh() {
      var request = new XMLHttpRequest();
      request.open("GET", "/api/state", true);
      request.setRequestHeader("Cache-Control", "no-store");
      request.onreadystatechange = function() {
        if (request.readyState !== 4) {
          return;
        }
        if (request.status < 200 || request.status >= 300) {
          renderUnavailable("Dashboard error (" + request.status + ")");
          return;
        }
        try {
          render(JSON.parse(request.responseText));
        } catch (error) {
          renderUnavailable("Dashboard parse error");
        }
      };
      request.onerror = function() {
        renderUnavailable("Dashboard unavailable");
      };
      request.send();
    }

    refresh();
    setInterval(refresh, 5000);
  </script>
</body>
</html>
"""
}
