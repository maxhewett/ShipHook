import Foundation
import Swifter

struct WebDashboardSnapshot: Codable {
    var generatedAt: Date
    var repositories: [Repository]

    struct Repository: Codable {
        var id: String
        var name: String
        var iconDataURL: String?
        var isEnabled: Bool
        var slug: String
        var branch: String
        var activity: String
        var phase: String
        var summary: String
        var releaseChannel: String?
        var version: String?
        var publishedVersion: String?
        var lastSeenSHA: String?
        var lastBuiltSHA: String?
        var lastCheckDate: Date?
        var lastSuccessDate: Date?
        var buildStartedAt: Date?
        var latestBuild: Build?
        var recentBuilds: [Build]
        var recentReleases: [Release]
        var progress: Progress?
        var lastCommitAuthorLogin: String?
        var lastCommitAuthorAvatarURL: String?
        var lastCommitAuthorProfileURL: String?
    }

    struct Build: Codable {
        var version: String
        var sha: String
        var builtAt: Date
        var releaseChannel: String?
        var authorLogin: String?
        var authorAvatarURL: String?
        var authorProfileURL: String?
        var summary: String?
        var logPath: String?
    }

    struct Release: Codable {
        var tagName: String
        var name: String
        var body: String
        var isPrerelease: Bool
        var publishedAt: Date?
        var htmlURL: String?
        var authorLogin: String?
        var authorAvatarURL: String?
        var authorProfileURL: String?
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
      --bg: radial-gradient(circle at 18% -10%, rgba(31,185,255,.20), transparent 36%), radial-gradient(circle at 100% 0%, rgba(52,211,153,.14), transparent 32%), linear-gradient(180deg,#0d1522 0%,#0b1118 100%);
      --surface: rgba(255,255,255,.08);
      --surface-2: rgba(255,255,255,.05);
      --border: rgba(255,255,255,.16);
      --text: rgba(255,255,255,.94);
      --muted: rgba(255,255,255,.64);
      --green: #36d39e;
      --orange: #ff9e4d;
      --red: #ff6f80;
      --blue: #63c9ff;
      --cyan: #52d8ff;
    }
    * { box-sizing: border-box; }
    body {
      margin: 0;
      min-height: 100vh;
      font: 14px/1.45 -apple-system, BlinkMacSystemFont, "SF Pro Text", sans-serif;
      background: var(--bg);
      color: var(--text);
    }
    .wrap { max-width: 1500px; margin: 0 auto; padding: 20px; }
    .hero {
      display: flex; justify-content: space-between; align-items: flex-end; gap: 16px;
      margin-bottom: 14px; padding: 14px;
      border-radius: 16px; border: 1px solid var(--border);
      background: rgba(255,255,255,.08);
      backdrop-filter: blur(20px) saturate(160%);
      -webkit-backdrop-filter: blur(20px) saturate(160%);
    }
    .hero h1 { margin: 0; font-size: 26px; letter-spacing: -.03em; }
    .hero p { margin: 4px 0 0; color: var(--muted); }
    .badge {
      border-radius: 999px; padding: 8px 12px;
      border: 1px solid var(--border); background: var(--surface-2); color: var(--muted);
    }
    .layout {
      display: grid;
      grid-template-columns: 320px minmax(0, 1fr);
      gap: 14px;
      min-height: calc(100vh - 130px);
    }
    .panel {
      border-radius: 16px; border: 1px solid var(--border);
      background: var(--surface);
      backdrop-filter: blur(20px) saturate(160%);
      -webkit-backdrop-filter: blur(20px) saturate(160%);
      box-shadow: 0 16px 40px rgba(0,0,0,.22);
    }
    .sidebar { padding: 12px; overflow: auto; }
    .repo-item {
      width: 100%; text-align: left; cursor: pointer;
      border: 1px solid rgba(255,255,255,.10);
      background: rgba(255,255,255,.04);
      border-radius: 12px; padding: 10px; margin-bottom: 8px;
      color: inherit;
    }
    .repo-item.active {
      border-color: rgba(99,201,255,.42);
      background: rgba(99,201,255,.14);
    }
    .repo-name { margin: 0; font-size: 14px; font-weight: 700; letter-spacing: -.01em; }
    .repo-sub { color: var(--muted); font-size: 12px; margin-top: 2px; white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
    .repo-top { display:flex; align-items: center; gap: 8px; }
    .repo-icon {
      width: 22px; height: 22px; border-radius: 8px;
      display:inline-flex; align-items: center; justify-content: center;
      font-size: 12px;
      border: 1px solid rgba(255,255,255,.16);
      background: rgba(255,255,255,.07);
      color: var(--text);
      flex-shrink: 0;
      object-fit: cover;
      overflow: hidden;
    }
    .repo-meta { display:flex; justify-content: space-between; gap: 8px; margin-top: 8px; align-items: center; }
    .status {
      display: inline-flex; align-items: center; gap: 6px;
      border-radius: 999px; padding: 4px 8px;
      border: 1px solid rgba(255,255,255,.18);
      font-size: 11px; font-weight: 700;
    }
    .status.idle, .status.succeeded { color: var(--green); background: rgba(54,211,158,.14); }
    .status.polling, .status.building { color: var(--blue); background: rgba(99,201,255,.14); }
    .status.failed { color: var(--red); background: rgba(255,111,128,.16); }
    .status.queued { color: var(--orange); background: rgba(255,158,77,.15); }
    .status.paused { color: var(--orange); background: rgba(255,158,77,.19); }
    .dot { width: 7px; height: 7px; border-radius: 999px; background: currentColor; }
    .version-chip {
      font-size: 11px; color: var(--muted);
      padding: 2px 7px; border-radius: 999px; border: 1px solid rgba(255,255,255,.14);
      background: rgba(255,255,255,.06);
    }
    .detail { padding: 14px; overflow: auto; }
    .detail-header { display:flex; justify-content: space-between; align-items: flex-start; gap: 12px; margin-bottom: 10px; }
    .detail-title-wrap { display:flex; align-items:center; gap: 10px; }
    .detail-icon {
      width: 28px; height: 28px; border-radius: 9px;
      border: 1px solid rgba(255,255,255,.16);
      background: rgba(255,255,255,.07);
      object-fit: cover;
      flex-shrink: 0;
    }
    .title { margin: 0; font-size: 23px; letter-spacing: -.03em; }
    .slug { color: var(--muted); font-size: 12px; margin-top: 3px; }
    .summary { margin: 10px 0 12px; }
    .author { display:flex; align-items:center; gap:8px; color: var(--muted); font-size: 12px; margin-bottom: 10px; }
    .avatar { width: 18px; height: 18px; border-radius: 999px; object-fit: cover; background: rgba(255,255,255,.12); }
    .tabs { display:flex; gap: 8px; margin-bottom: 12px; }
    .tab {
      cursor: pointer; border: 1px solid rgba(255,255,255,.16);
      background: rgba(255,255,255,.05); color: var(--muted);
      border-radius: 10px; padding: 7px 12px; font-size: 12px; font-weight: 700;
    }
    .tab.active {
      color: var(--text);
      border-color: rgba(99,201,255,.42);
      background: rgba(99,201,255,.16);
    }
    .card-grid { display:grid; grid-template-columns: repeat(2, minmax(0, 1fr)); gap: 10px; margin-bottom: 12px; }
    .metric {
      border-radius: 12px; border: 1px solid rgba(255,255,255,.12);
      background: var(--surface-2); padding: 10px;
    }
    .metric strong { display:block; color: var(--muted); font-size: 11px; margin-bottom: 2px; font-weight: 600; }
    .metric span { font-weight: 700; }
    .row { display:flex; justify-content: space-between; gap: 10px; color: var(--muted); font-size: 12px; margin-bottom: 8px; }
    .channel {
      display:inline-flex; align-items:center; gap:6px;
      font-size: 11px; font-weight: 700;
      padding: 2px 8px; border-radius: 999px;
      border: 1px solid rgba(255,158,77,.36); color: var(--orange); background: rgba(255,158,77,.16);
      margin-left: 6px;
    }
    .progress-wrap { margin: 10px 0 14px; }
    .progress-label { display:flex; justify-content: space-between; color: var(--muted); font-size: 12px; margin-bottom: 6px; }
    .progress { height: 8px; border-radius: 999px; overflow: hidden; background: rgba(255,255,255,.10); }
    .bar { height: 100%; border-radius: inherit; background: linear-gradient(90deg, var(--cyan), var(--green)); }
    .split { display:grid; grid-template-columns: 1fr 1fr; gap: 10px; }
    .pane {
      border-radius: 12px; border: 1px solid rgba(255,255,255,.11);
      background: rgba(255,255,255,.04); padding: 10px;
      min-height: 220px;
    }
    .stack { display:grid; grid-template-columns: 1fr; gap: 10px; }
    .explorer-head {
      display:flex; justify-content: space-between; gap: 10px; align-items: center;
      margin-bottom: 8px;
    }
    .explore-btn {
      cursor: pointer;
      border: 1px solid rgba(255,255,255,.16);
      background: rgba(255,255,255,.08);
      color: var(--text);
      border-radius: 9px;
      font-size: 12px;
      font-weight: 700;
      padding: 5px 10px;
    }
    .section-title { color: var(--muted); text-transform: uppercase; letter-spacing: .08em; font-size: 11px; margin: 0 0 8px; }
    .section-icon { margin-right: 6px; opacity: .9; }
    .list-item {
      border-radius: 10px; border: 1px solid rgba(255,255,255,.09);
      background: rgba(255,255,255,.03); padding: 9px; margin-bottom: 7px; font-size: 12px;
    }
    .list-title { font-weight: 700; }
    .list-meta { color: var(--muted); margin-top: 2px; }
    .list-body { color: var(--muted); margin-top: 4px; white-space: pre-wrap; max-height: 72px; overflow: auto; }
    .notes-html { white-space: normal; line-height: 1.36; max-height: 84px; }
    .notes-html * { margin: 0 0 6px 0; font-size: 12px; max-width: 100%; }
    .notes-html img { max-width: 100%; height: auto; }
    .modal .notes-html { max-height: 220px; }
    .more-label { color: var(--muted); font-size: 12px; margin-top: 4px; }
    .modal-backdrop {
      position: fixed; inset: 0; z-index: 100;
      background: rgba(7,11,18,.56);
      backdrop-filter: blur(4px);
      display: none;
      align-items: center; justify-content: center;
      padding: 20px;
    }
    .modal {
      width: min(980px, 96vw);
      max-height: 88vh;
      overflow: auto;
      border-radius: 16px; border: 1px solid var(--border);
      background: rgba(18,28,42,.86);
      padding: 14px;
      box-shadow: 0 24px 54px rgba(0,0,0,.35);
    }
    .modal-head {
      position: sticky; top: 0;
      display:flex; justify-content: space-between; align-items: center; gap: 10px;
      padding-bottom: 10px; margin-bottom: 10px;
      background: rgba(18,28,42,.86);
      border-bottom: 1px solid rgba(255,255,255,.10);
    }
    .modal-actions { display:flex; gap: 8px; align-items: center; }
    .modal-btn {
      cursor: pointer;
      border: 1px solid rgba(255,255,255,.16);
      background: rgba(255,255,255,.08);
      color: var(--text);
      border-radius: 9px;
      font-size: 12px;
      font-weight: 700;
      padding: 6px 10px;
    }
    .modal-btn[disabled] { opacity: .45; cursor: default; }
    .empty { color: var(--muted); font-size: 13px; }
    a { color: inherit; }
    @media (max-width: 980px) {
      .layout { grid-template-columns: 1fr; min-height: auto; }
      .card-grid { grid-template-columns: 1fr; }
      .split { grid-template-columns: 1fr; }
    }
  </style>
</head>
<body>
  <div class="wrap">
    <header class="hero">
      <div>
        <h1>ShipHook Dashboard</h1>
        <p>Repo-focused view with status and explorers.</p>
      </div>
      <div class="badge" id="updatedAt">Waiting for first refresh</div>
    </header>
    <div class="layout">
      <aside class="panel sidebar" id="repoList"></aside>
      <section class="panel detail" id="repoDetail"></section>
    </div>
    <div class="modal-backdrop" id="explorerModal"></div>
  </div>
  <script>
    var dashboardState = { repositories: [] };
    var selectedRepoID = null;
    var selectedTab = "status";
    var explorerType = null;
    var explorerPage = 0;

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
      if (repo.isEnabled === false) return "paused";
      if (repo.phase === "queued") return "queued";
      if (repo.activity === "failed") return "failed";
      if (repo.activity === "polling") return "polling";
      if (repo.activity === "building") return "building";
      if (repo.activity === "succeeded") return "succeeded";
      return "idle";
    }

    function statusText(repo) {
      if (repo.isEnabled === false) return "Paused";
      if (repo.phase === "queued") return "Queued";
      return String(repo.activity || "idle");
    }

    function statusIcon(repo) {
      if (repo.isEnabled === false) return "⏸";
      if (repo.phase === "queued") return "⏳";
      if (repo.activity === "failed") return "❌";
      if (repo.activity === "building") return "🛠";
      if (repo.activity === "polling") return "🔄";
      if (repo.activity === "succeeded") return "✅";
      return "○";
    }

    function betaBadge(channel) {
      return channel === "beta" ? '<span class="channel">Beta</span>' : "";
    }

    function renderAuthor(login, avatarURL, profileURL, suffix) {
      if (!login) return "";
      var avatar = avatarURL
        ? '<img class="avatar" src="' + escapeHtml(avatarURL) + '" alt="avatar">'
        : '<span class="avatar"></span>';
      var label = login.startsWith("@") ? login : ("@" + login);
      var user = profileURL
        ? '<a href="' + escapeHtml(profileURL) + '" target="_blank" rel="noreferrer">' + escapeHtml(label) + '</a>'
        : escapeHtml(label);
      return '<div class="author">' + avatar + '<span>' + user + " " + escapeHtml(suffix || "") + '</span></div>';
    }

    function repoIconMarkup(repo, cls) {
      if (repo && repo.iconDataURL) {
        return '<img class="' + cls + '" src="' + escapeHtml(repo.iconDataURL) + '" alt="app icon">';
      }
      return '<span class="' + cls + '">📦</span>';
    }

    function setSelectedRepo(repoID) {
      selectedRepoID = repoID;
      try { localStorage.setItem("shiphook-web-selected-repo", repoID); } catch (_) {}
      renderUI();
    }

    function setTab(tab) {
      selectedTab = tab;
      renderUI();
    }

    function openExplorer(type) {
      explorerType = type;
      explorerPage = 0;
      renderExplorerModal(getSelectedRepo());
    }

    function closeExplorer() {
      explorerType = null;
      renderExplorerModal(getSelectedRepo());
    }

    function moveExplorerPage(delta) {
      explorerPage += delta;
      if (explorerPage < 0) explorerPage = 0;
      renderExplorerModal(getSelectedRepo());
    }

    function getSelectedRepo() {
      var repos = dashboardState.repositories || [];
      if (!repos.length) return null;
      if (!selectedRepoID || !repos.some(function(r) { return r.id === selectedRepoID; })) {
        selectedRepoID = repos[0].id;
      }
      return repos.find(function(r) { return r.id === selectedRepoID; }) || repos[0];
    }

    function renderSidebar() {
      var repos = dashboardState.repositories || [];
      var root = document.getElementById("repoList");
      if (!repos.length) {
        root.innerHTML = '<div class="empty">No repositories configured yet.</div>';
        return;
      }
      var items = repos.map(function(repo) {
        var active = repo.id === selectedRepoID ? " active" : "";
        return (
          '<button class="repo-item' + active + '" onclick="setSelectedRepo(\\'' + escapeHtml(repo.id) + '\\')">' +
            '<div class="repo-top">' + repoIconMarkup(repo, "repo-icon") + '<div class="repo-name">' + escapeHtml(repo.name) + '</div></div>' +
            '<div class="repo-sub">' + escapeHtml(repo.slug) + "</div>" +
            '<div class="repo-meta">' +
              '<span class="status ' + statusClass(repo) + '"><span class="dot"></span>' + escapeHtml(statusIcon(repo) + " " + statusText(repo)) + '</span>' +
              '<span class="version-chip">v' + escapeHtml(repo.version || "Unknown") + '</span>' +
            '</div>' +
          '</button>'
        );
      }).join("");
      root.innerHTML = items;
    }

    function renderBuildItems(builds) {
      return builds.map(function(build) {
        var author = renderAuthor(build.authorLogin, build.authorAvatarURL, build.authorProfileURL, "committed this build");
        var summary = build.summary ? '<div class="list-body">' + escapeHtml(build.summary) + '</div>' : "";
        return (
          '<div class="list-item">' +
            '<div class="list-title">v' + escapeHtml(build.version || "Unknown") + betaBadge(build.releaseChannel) + '</div>' +
            '<div class="list-meta">' + escapeHtml(shortSHA(build.sha)) + " · " + escapeHtml(formatDate(build.builtAt)) + '</div>' +
            summary + author +
          '</div>'
        );
      }).join("");
    }

    function looksLikeHTML(value) {
      return /<[^>]+>/.test(value || "");
    }

    function stripHTML(value) {
      return String(value || "").replace(/<[^>]*>/g, " ").replace(/\\s+/g, " ").trim();
    }

    function truncate(value, limit) {
      if (!value || value.length <= limit) return value;
      return value.slice(0, limit - 1).trim() + "…";
    }

    function releaseBodyMarkup(body, fullNotes) {
      if (!body) return "";
      if (looksLikeHTML(body)) {
        if (!fullNotes) {
          return '<div class="list-body">' + escapeHtml(truncate(stripHTML(body), 220)) + '</div>';
        }
        return '<div class="list-body notes-html">' + body + '</div>';
      }
      if (!fullNotes) {
        return '<div class="list-body">' + escapeHtml(truncate(body, 220)).replace(/\\n/g, "<br>") + '</div>';
      }
      return '<div class="list-body">' + escapeHtml(body).replace(/\\n/g, "<br>") + '</div>';
    }

    function renderReleaseItems(releases, fullNotes) {
      return releases.map(function(release) {
        var author = renderAuthor(release.authorLogin, release.authorAvatarURL, release.authorProfileURL, "published this release");
        var body = releaseBodyMarkup(release.body || "", !!fullNotes);
        var link = release.htmlURL ? '<a href="' + escapeHtml(release.htmlURL) + '" target="_blank" rel="noreferrer">Open release</a>' : "";
        return (
          '<div class="list-item">' +
            '<div class="list-title">' + escapeHtml(release.tagName) + betaBadge(release.isPrerelease ? "beta" : "") + '</div>' +
            '<div class="list-meta">' + escapeHtml(formatDate(release.publishedAt)) + '</div>' +
            '<div class="list-meta">' + escapeHtml(release.name || "") + '</div>' +
            body + author +
            (link ? '<div class="list-meta">' + link + '</div>' : '') +
          '</div>'
        );
      }).join("");
    }

    function renderBuildExplorerPreview(repo) {
      var builds = repo.recentBuilds || [];
      if (!builds.length) return '<div class="empty">No recent builds yet.</div>';
      var preview = builds.slice(0, 2);
      var remaining = Math.max(0, builds.length - preview.length);
      return (
        renderBuildItems(preview) +
        (remaining > 0 ? '<div class="more-label">' + remaining + " more build" + (remaining === 1 ? "" : "s") + '.</div>' : '')
      );
    }

    function renderReleaseExplorerPreview(repo) {
      var releases = repo.recentReleases || [];
      if (!releases.length) return '<div class="empty">No releases loaded yet.</div>';
      var preview = releases.slice(0, 2);
      var remaining = Math.max(0, releases.length - preview.length);
      return (
        renderReleaseItems(preview, false) +
        (remaining > 0 ? '<div class="more-label">' + remaining + " more release" + (remaining === 1 ? "" : "s") + '.</div>' : '')
      );
    }

    function renderExplorerModal(repo) {
      var modalRoot = document.getElementById("explorerModal");
      if (!repo || !explorerType) {
        modalRoot.style.display = "none";
        modalRoot.innerHTML = "";
        return;
      }

      var items = explorerType === "build" ? (repo.recentBuilds || []) : (repo.recentReleases || []);
      var title = explorerType === "build" ? "Build Explorer" : "Release Explorer";
      var pageSize = 10;
      var totalPages = Math.max(1, Math.ceil(items.length / pageSize));
      if (explorerPage > totalPages - 1) explorerPage = totalPages - 1;
      var start = explorerPage * pageSize;
      var pageItems = items.slice(start, start + pageSize);
      var listHTML = explorerType === "build" ? renderBuildItems(pageItems) : renderReleaseItems(pageItems, true);

      modalRoot.innerHTML =
        '<div class="modal">' +
          '<div class="modal-head">' +
            '<div><strong>' + (explorerType === "build" ? "🧱 " : "🧪 ") + escapeHtml(title) + '</strong><div class="list-meta">' + escapeHtml(repo.name) + '</div></div>' +
            '<div class="modal-actions">' +
              '<span class="list-meta">Page ' + (explorerPage + 1) + " of " + totalPages + '</span>' +
              '<button class="modal-btn" ' + (explorerPage === 0 ? "disabled" : "") + ' onclick="moveExplorerPage(-1)">Previous</button>' +
              '<button class="modal-btn" ' + (explorerPage >= totalPages - 1 ? "disabled" : "") + ' onclick="moveExplorerPage(1)">Next</button>' +
              '<button class="modal-btn" onclick="closeExplorer()">Done</button>' +
            '</div>' +
          '</div>' +
          (pageItems.length ? listHTML : '<div class="empty">Nothing to show.</div>') +
        '</div>';

      modalRoot.style.display = "flex";
    }

    function renderDetail() {
      var repo = getSelectedRepo();
      var root = document.getElementById("repoDetail");
      if (!repo) {
        root.innerHTML = '<div class="empty">Select a repository.</div>';
        return;
      }

      var author = renderAuthor(repo.lastCommitAuthorLogin, repo.lastCommitAuthorAvatarURL, repo.lastCommitAuthorProfileURL, "published this commit");
      var progress = "";
      if (repo.progress) {
        var width = Math.max(0, Math.min(100, repo.progress.fractionComplete * 100));
        progress =
          '<div class="progress-wrap">' +
            '<div class="progress-label"><span>Step ' + repo.progress.currentStep + " of " + repo.progress.totalSteps + '</span><span>' + escapeHtml(repo.progress.label) + '</span></div>' +
            '<div class="progress"><div class="bar" style="width:' + width + '%"></div></div>' +
          '</div>';
      }

      var tabButtons =
        '<div class="tabs">' +
          '<button class="tab' + (selectedTab === "status" ? ' active' : '') + '" onclick="setTab(\\'status\\')">📊 Status</button>' +
          '<button class="tab' + (selectedTab === "explorers" ? ' active' : '') + '" onclick="setTab(\\'explorers\\')">🧭 Builds & Releases</button>' +
        '</div>';

      var statusPane =
        '<div class="split">' +
          '<div class="pane">' +
            '<div class="section-title"><span class="section-icon">📌</span>Current</div>' +
            '<div class="card-grid">' +
              '<div class="metric"><strong>Current Version</strong><span>' + escapeHtml(repo.version || "Unknown") + betaBadge(repo.releaseChannel) + '</span></div>' +
              '<div class="metric"><strong>Published Version</strong><span>' + escapeHtml(repo.publishedVersion || "Unknown") + '</span></div>' +
            '</div>' +
            '<div class="row"><span>Status</span><span>' + escapeHtml(statusText(repo)) + '</span></div>' +
            '<div class="row"><span>Phase</span><span>' + escapeHtml(repo.phase || "idle") + '</span></div>' +
          '</div>' +
          '<div class="pane">' +
            '<div class="section-title"><span class="section-icon">🕒</span>Timeline</div>' +
            '<div class="row"><span>Latest Seen</span><span>' + escapeHtml(shortSHA(repo.lastSeenSHA)) + " · " + escapeHtml(formatDate(repo.lastCheckDate)) + '</span></div>' +
            '<div class="row"><span>Latest Built</span><span>' + escapeHtml(shortSHA(repo.lastBuiltSHA)) + " · " + escapeHtml(formatDate(repo.lastSuccessDate)) + '</span></div>' +
            '<div class="row"><span>Branch</span><span>' + escapeHtml(repo.branch || "") + '</span></div>' +
          '</div>' +
        '</div>';

      var explorersPane =
        '<div class="stack">' +
          '<div class="pane">' +
            '<div class="explorer-head"><div class="section-title"><span class="section-icon">🧱</span>Build Explorer</div><button class="explore-btn" onclick="openExplorer(\\'build\\')">Explore</button></div>' +
            renderBuildExplorerPreview(repo) +
          '</div>' +
          '<div class="pane">' +
            '<div class="explorer-head"><div class="section-title"><span class="section-icon">🧪</span>Release Explorer</div><button class="explore-btn" onclick="openExplorer(\\'release\\')">Explore</button></div>' +
            renderReleaseExplorerPreview(repo) +
          '</div>' +
        '</div>';

      root.innerHTML =
        '<div class="detail-header">' +
          '<div class="detail-title-wrap">' + repoIconMarkup(repo, "detail-icon") + '<div><h2 class="title">' + escapeHtml(repo.name) + '</h2><div class="slug">' + escapeHtml(repo.slug) + " · " + escapeHtml(repo.branch) + '</div></div></div>' +
          '<div class="status ' + statusClass(repo) + '"><span class="dot"></span>' + escapeHtml(statusIcon(repo) + " " + statusText(repo)) + '</div>' +
        '</div>' +
        '<p class="summary">' + escapeHtml(repo.summary || "") + '</p>' +
        author +
        progress +
        tabButtons +
        (selectedTab === "status" ? statusPane : explorersPane);
    }

    function renderUI() {
      renderSidebar();
      renderDetail();
      renderExplorerModal(getSelectedRepo());
    }

    function render(state) {
      dashboardState = state || { repositories: [] };
      document.getElementById("updatedAt").textContent = "Updated " + formatDate(dashboardState.generatedAt);
      if (!selectedRepoID) {
        try { selectedRepoID = localStorage.getItem("shiphook-web-selected-repo"); } catch (_) {}
      }
      renderUI();
    }

    function renderUnavailable(message) {
      document.getElementById("updatedAt").textContent = message;
      dashboardState = { repositories: [] };
      document.getElementById("repoList").innerHTML = '<div class="empty">' + escapeHtml(message) + '</div>';
      document.getElementById("repoDetail").innerHTML = '<div class="empty">' + escapeHtml(message) + '</div>';
    }

    function refresh() {
      var request = new XMLHttpRequest();
      request.open("GET", "/api/state", true);
      request.setRequestHeader("Cache-Control", "no-store");
      request.onreadystatechange = function() {
        if (request.readyState !== 4) return;
        if (request.status < 200 || request.status >= 300) {
          renderUnavailable("Dashboard error (" + request.status + ")");
          return;
        }
        try { render(JSON.parse(request.responseText)); }
        catch (_) { renderUnavailable("Dashboard parse error"); }
      };
      request.onerror = function() { renderUnavailable("Dashboard unavailable"); };
      request.send();
    }

    refresh();
    setInterval(refresh, 5000);
  </script>
</body>
</html>
"""
}
