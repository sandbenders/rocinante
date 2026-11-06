// SPDX-License-Identifier: 0BSD
//
// Dear ImGui's current-context pointer, one for each thread, so the unit tests (which run in
// parallel threads) can each have a context of their own. See "How can I use multiple
// contexts" in imgui.cpp. The pointer itself is defined in roci_context.cpp.
#pragma once
struct ImGuiContext;
extern thread_local ImGuiContext* RociImGuiContext;
#define GImGui RociImGuiContext
