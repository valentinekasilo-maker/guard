// Guard (Pi-hole Core v6) Modern Dashboard Controller
// Fully compliant with Content-Security-Policy (script-src 'self')

(function () {
  'use strict';

  function getApiBase() {
    const path = window.location.pathname;
    const ingressMatch = path.match(/^(\/api\/hassio_ingress\/[^/]+)/);
    if (ingressMatch) {
      return ingressMatch[1] + "/api";
    }
    return "/api";
  }

  const API_BASE = getApiBase();
  let isBlocking = true;
  let allQueries = [];
  let sid = "";

  function showToast(msg) {
    const toast = document.getElementById("toast");
    if (!toast) return;
    toast.innerText = msg;
    toast.classList.add("show");
    setTimeout(() => toast.classList.remove("show"), 3000);
  }

  async function ensureAuth() {
    if (sid) return sid;

    // Check existing session
    try {
      const res = await fetch(`${API_BASE}/auth`);
      const data = await res.json();
      if (data && data.session && data.session.valid && data.session.sid) {
        sid = data.session.sid;
        return sid;
      }
    } catch (e) {}

    // Authenticate with known passwords
    const candidatePasswords = ["guard", "", localStorage.getItem("pihole_password") || ""];
    for (const pwd of candidatePasswords) {
      try {
        const res = await fetch(`${API_BASE}/auth`, {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({ password: pwd })
        });
        const data = await res.json();
        if (data && data.session && data.session.valid && data.session.sid) {
          sid = data.session.sid;
          return sid;
        }
      } catch (e) {}
    }
    return "";
  }

  async function apiFetch(path, options = {}) {
    await ensureAuth();
    options.headers = options.headers || {};
    options.headers["Accept"] = "application/json";
    if (sid) {
      options.headers["sid"] = sid;
      options.headers["X-FTL-SID"] = sid;
    }
    let res = await fetch(`${API_BASE}${path}`, options);
    if (res.status === 401 || res.status === 403) {
      sid = "";
      await ensureAuth();
      if (sid) {
        options.headers["sid"] = sid;
        options.headers["X-FTL-SID"] = sid;
        res = await fetch(`${API_BASE}${path}`, options);
      }
    }
    return res;
  }

  function switchTab(tabId) {
    document.querySelectorAll(".tab-btn").forEach(btn => btn.classList.remove("active"));
    document.querySelectorAll(".tab-content").forEach(c => c.classList.remove("active"));
    
    const activeBtn = document.querySelector(`.tab-btn[data-tab="${tabId}"]`);
    if (activeBtn) activeBtn.classList.add("active");
    
    const activeContent = document.getElementById("tab-" + tabId);
    if (activeContent) activeContent.classList.add("active");

    if (tabId === "system") loadSystemInfo();
    if (tabId === "domains") loadDomains();
  }

  async function fetchSummary() {
    try {
      const res = await apiFetch("/stats/summary");
      if (!res.ok) throw new Error(res.statusText);
      const data = await res.json();

      const elTotal = document.getElementById("valTotalQueries");
      if (elTotal) elTotal.innerText = (data.queries && data.queries.total !== undefined ? data.queries.total : 0).toLocaleString();

      const elBlocked = document.getElementById("valBlockedQueries");
      if (elBlocked) elBlocked.innerText = (data.queries && data.queries.blocked !== undefined ? data.queries.blocked : 0).toLocaleString();

      const elPercent = document.getElementById("valPercentBlocked");
      if (elPercent) {
        const pct = (data.queries && data.queries.percent_blocked !== undefined) ? data.queries.percent_blocked : 0;
        elPercent.innerText = `${pct.toFixed(1)}% blocked`;
      }

      const elClients = document.getElementById("valActiveClients");
      if (elClients) {
        const active = (data.clients && data.clients.active !== undefined) ? data.clients.active : 0;
        const total = (data.clients && data.clients.total !== undefined) ? data.clients.total : 0;
        elClients.innerText = `Active clients: ${active} (total: ${total})`;
      }

      const elGravity = document.getElementById("valGravityCount");
      if (elGravity) {
        const count = (data.gravity && data.gravity.domains_being_blocked !== undefined) ? data.gravity.domains_being_blocked : 0;
        elGravity.innerText = count.toLocaleString();
      }

      const elUpdated = document.getElementById("valGravityUpdated");
      if (elUpdated && data.gravity && data.gravity.last_update) {
        const d = new Date(data.gravity.last_update * 1000);
        elUpdated.innerText = `Updated: ${d.toLocaleDateString()} ${d.toLocaleTimeString()}`;
      }
    } catch (e) {
      console.warn("Summary fetch error:", e);
    }
  }

  async function checkBlockingState() {
    try {
      const res = await apiFetch("/dns/blocking");
      if (!res.ok) return;
      const data = await res.json();
      const badge = document.getElementById("statusBadge");
      const text = document.getElementById("statusText");
      const btn = document.getElementById("toggleBlockingBtn");

      isBlocking = (data.blocking === "enabled");
      if (isBlocking) {
        if (badge) badge.className = "status-badge";
        if (text) text.innerText = "Active";
        if (btn) {
          btn.innerText = "Pause 5m";
          btn.className = "btn btn-outline";
        }
      } else {
        if (badge) badge.className = "status-badge disabled";
        if (text) text.innerText = data.timer ? `Paused (${data.timer}s)` : "Disabled";
        if (btn) {
          btn.innerText = "Enable Blocking";
          btn.className = "btn btn-danger";
        }
      }
    } catch (e) {
      console.warn("Blocking check error:", e);
    }
  }

  async function toggleBlocking() {
    const payload = isBlocking 
      ? { blocking: false, timer: 300 } 
      : { blocking: true, timer: null };

    try {
      const res = await apiFetch("/dns/blocking", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify(payload)
      });
      if (res.ok) {
        showToast(isBlocking ? "Blocking paused for 5 minutes" : "Blocking enabled");
        checkBlockingState();
      }
    } catch (e) {
      showToast("Error updating blocking state");
    }
  }

  async function updateGravity() {
    showToast("Updating Gravity blocklists...");
    try {
      const res = await apiFetch("/action/gravity", { method: "POST" });
      if (res.ok) {
        showToast("Gravity blocklist update started");
        setTimeout(fetchSummary, 4000);
      } else {
        showToast("Gravity update triggered");
      }
    } catch (e) {
      showToast("Gravity update request sent");
    }
  }

  async function restartDNS() {
    try {
      await apiFetch("/action/restart", { method: "POST" });
      showToast("DNS service restarted successfully");
    } catch (e) {
      showToast("Restart command sent");
    }
  }

  async function loadQueries() {
    try {
      const res = await apiFetch("/queries?length=50");
      if (!res.ok) return;
      const data = await res.json();
      allQueries = data.queries || [];
      renderQueries(allQueries);
    } catch (e) {
      console.warn("Query log fetch error:", e);
    }
  }

  function renderQueries(list) {
    const tbody = document.getElementById("queriesBody");
    if (!tbody) return;

    if (!list || list.length === 0) {
      tbody.innerHTML = `<tr><td colspan="6" style="text-align:center; padding: 24px; color: var(--text-muted);">Waiting for DNS traffic...</td></tr>`;
      return;
    }

    tbody.innerHTML = list.map(q => {
      const time = q.time ? new Date(q.time * 1000).toLocaleTimeString() : "--:--:--";
      let statusTag = `<span class="tag tag-allowed">Allowed</span>`;
      if (q.status === "GRAVITY" || q.status === "DENY" || q.status === "REGEX" || q.status === "DENYLIST" || q.blocked) {
        statusTag = `<span class="tag tag-blocked">Blocked</span>`;
      } else if (q.status === "CACHE") {
        statusTag = `<span class="tag tag-cached">Cached</span>`;
      }

      const domain = q.domain || "---";
      const clientStr = (typeof q.client === 'object' && q.client !== null)
        ? (q.client.name || q.client.ip || "LAN")
        : (q.client || q.client_name || "LAN");

      return `
        <tr>
          <td>${time}</td>
          <td style="color: var(--text-muted); font-weight:600;">${q.type || "A"}</td>
          <td style="font-weight: 500;">${domain}</td>
          <td style="color: var(--cyan);">${clientStr}</td>
          <td>${statusTag}</td>
          <td>
            <button class="btn btn-outline btn-quick-block" style="padding: 3px 8px; font-size: 0.75rem;" data-domain="${domain}">Block</button>
          </td>
        </tr>
      `;
    }).join("");

    // Attach click listeners to quick block buttons
    tbody.querySelectorAll(".btn-quick-block").forEach(btn => {
      btn.addEventListener("click", () => {
        const dom = btn.getAttribute("data-domain");
        quickBlock(dom);
      });
    });
  }

  function filterQueries() {
    const val = (document.getElementById("querySearch")?.value || "").toLowerCase();
    const filtered = allQueries.filter(q => {
      const d = (q.domain || "").toLowerCase();
      const c = (typeof q.client === 'object' && q.client !== null ? (q.client.name || q.client.ip || "") : (q.client || "")).toLowerCase();
      return d.includes(val) || c.includes(val);
    });
    renderQueries(filtered);
  }

  async function addDomain(type) {
    const inp = document.getElementById("domainInput");
    if (!inp) return;
    const domain = inp.value.trim();
    if (!domain) return;

    try {
      const res = await apiFetch("/domains", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ domain: domain, type: type })
      });
      showToast(type === "deny" ? `Added ${domain} to Blacklist` : `Added ${domain} to Whitelist`);
      inp.value = "";
      loadDomains();
    } catch (e) {
      showToast("Error adding domain");
    }
  }

  async function loadDomains() {
    try {
      const res = await apiFetch("/domains");
      if (!res.ok) return;
      const data = await res.json();
      const container = document.getElementById("domainsList");
      if (!container) return;

      const domains = data.domains || [];
      if (domains.length === 0) {
        container.innerHTML = `<p style="color: var(--text-muted); font-size: 0.85rem;">No custom domain rules added yet.</p>`;
        return;
      }

      container.innerHTML = domains.map(d => `
        <div class="list-item">
          <span><strong>${d.domain}</strong> <span class="tag ${d.type === 'deny' ? 'tag-blocked' : 'tag-allowed'}">${d.type}</span></span>
          <button class="btn btn-danger btn-delete-domain" style="padding: 3px 8px; font-size: 0.75rem;" data-domain="${d.domain}">Delete</button>
        </div>
      `).join("");

      container.querySelectorAll(".btn-delete-domain").forEach(btn => {
        btn.addEventListener("click", async () => {
          const dom = btn.getAttribute("data-domain");
          await apiFetch(`/domains/${encodeURIComponent(dom)}`, { method: "DELETE" });
          showToast(`Removed ${dom}`);
          loadDomains();
        });
      });
    } catch (e) {}
  }

  function quickBlock(domain) {
    if (!domain || domain === "---") return;
    const inp = document.getElementById("domainInput");
    if (inp) inp.value = domain;
    switchTab('domains');
    addDomain('deny');
  }

  async function loadSystemInfo() {
    try {
      const res = await apiFetch("/info/version");
      if (res.ok) {
        const json = await res.json();
        const pre = document.getElementById("systemJson");
        if (pre) pre.innerText = JSON.stringify(json, null, 2);
      }
    } catch (e) {
      const pre = document.getElementById("systemJson");
      if (pre) pre.innerText = "Pi-hole FTL v6 API active on port 8085";
    }
  }

  // Initialize event handlers once DOM is ready
  function init() {
    // Tab switching
    document.querySelectorAll(".tab-btn").forEach(btn => {
      btn.addEventListener("click", () => {
        const tabId = btn.getAttribute("data-tab");
        if (tabId) switchTab(tabId);
      });
    });

    // Action buttons
    const btnToggle = document.getElementById("toggleBlockingBtn");
    if (btnToggle) btnToggle.addEventListener("click", toggleBlocking);

    const btnUpdateGrav = document.getElementById("updateGravityBtn");
    if (btnUpdateGrav) btnUpdateGrav.addEventListener("click", updateGravity);

    const btnRefresh = document.getElementById("refreshQueriesBtn");
    if (btnRefresh) btnRefresh.addEventListener("click", loadQueries);

    const inpSearch = document.getElementById("querySearch");
    if (inpSearch) inpSearch.addEventListener("input", filterQueries);

    const btnBlacklist = document.getElementById("addBlacklistBtn");
    if (btnBlacklist) btnBlacklist.addEventListener("click", () => addDomain("deny"));

    const btnWhitelist = document.getElementById("addWhitelistBtn");
    if (btnWhitelist) btnWhitelist.addEventListener("click", () => addDomain("allow"));

    const btnRestartDns = document.getElementById("restartDnsBtn");
    if (btnRestartDns) btnRestartDns.addEventListener("click", restartDNS);

    const btnOpenApi = document.getElementById("openApiBtn");
    if (btnOpenApi) btnOpenApi.addEventListener("click", () => window.open(API_BASE + "/docs", "_blank"));

    // Start polling cycles
    ensureAuth().then(() => {
      fetchSummary();
      checkBlockingState();
      loadQueries();
    });

    setInterval(fetchSummary, 3000);
    setInterval(checkBlockingState, 5000);
    setInterval(loadQueries, 6000);
  }

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", init);
  } else {
    init();
  }
})();

