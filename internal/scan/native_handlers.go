package scan

import (
	"encoding/json"
	"fmt"
	"net"
	"reflect"
	"sort"
	"strings"
	"time"

	"github.com/KubeDeckio/KubeBuddy/internal/checks"
)

type nativeHandler func(check checks.Check, item map[string]any, cache map[string][]map[string]any) ([]Finding, error)

var nativeHandlers = map[string]nativeHandler{
	"CFG001":          runCFG001,
	"CFG002":          runCFG002,
	"CFG003":          runCFG003,
	"JOB001":          runJOB001,
	"JOB002":          runJOB002,
	"NS001":           runNS001,
	"NS002":           runNS002,
	"NS003":           runNS003,
	"NS004":           runNS004,
	"POD001":          runPOD001,
	"POD002":          runPOD002,
	"POD006":          runPOD006,
	"POD007":          runPOD007,
	"POD008":          runPOD008,
	"RBAC001":         runRBAC001,
	"RBAC002":         runRBAC002,
	"RBAC003":         runRBAC003,
	"RBAC004":         runRBAC004,
	"SEC001":          runSEC001,
	"SEC002":          runSEC002,
	"SEC003":          runSEC003,
	"SEC004":          runSEC004,
	"SEC005":          runSEC005,
	"SEC006":          runSEC006,
	"SEC007":          runSEC007,
	"SEC008":          runSEC008,
	"SEC009":          runSEC009,
	"SEC010":          runSEC010,
	"SEC011":          runSEC011,
	"SEC012":          runSEC012,
	"SEC013":          runSEC013,
	"SEC014":          runSEC014,
	"SEC016":          runSEC016,
	"SEC017":          runSEC017,
	"SEC019":          runSEC019,
	"SEC020":          runSEC020,
	"NODE001":         runNODE001,
	"NODE002":         runNODE002,
	"NODE003":         runNODE003,
	"NET001":          runNET001,
	"NET002":          runNET002,
	"NET003":          runNET003,
	"NET004":          runNET004,
	"NET005":          runNET005,
	"NET006":          runNET006,
	"NET007":          runNET007,
	"NET008":          runNET008,
	"NET009":          runNET009,
	"NET010":          runNET010,
	"NET011":          runNET011,
	"NET012":          runNET012,
	"NET013":          runNET013,
	"NET014":          runNET014,
	"NET015":          runNET015,
	"NET016":          runNET016,
	"NET017":          runNET017,
	"NET018":          runNET018,
	"PV001":           runPV001,
	"PVC001":          runPVC001,
	"PVC003":          runPVC003,
	"SC002_AKS":       runSC002AKS,
	"SC002_EXPANSION": runSC002Expansion,
	"SC003":           runSC003,
	"PROM006":         runPROM006,
	"PROM007":         runPROM007,
	"WRK001":          runWRK001,
	"WRK002":          runWRK002,
	"WRK003":          runWRK003,
	"WRK004":          runWRK004,
	"WRK005":          runWRK005,
	"WRK006":          runWRK006,
	"WRK007":          runWRK007,
	"WRK008":          runWRK008,
	"WRK009":          runWRK009,
	"WRK010":          runWRK010,
	"WRK011":          runWRK011,
	"WRK012":          runWRK012,
	"WRK013":          runWRK013,
	"WRK014":          runWRK014,
	"WRK015":          runWRK015,
}

func executeNativeHandler(check checks.Check, items []map[string]any, cache map[string][]map[string]any) ([]Finding, bool, error) {
	name := strings.TrimSpace(check.NativeHandler)
	if name == "" {
		name = strings.TrimSpace(check.ID)
	}

	if name == "EVENT001" {
		return runEVENT001(check, items), true, nil
	}
	if name == "EVENT002" {
		return runEVENT002(check, items), true, nil
	}

	handler, ok := nativeHandlers[name]
	if !ok {
		return nil, false, nil
	}

	var findings []Finding
	for _, item := range items {
		entries, err := handler(check, item, cache)
		if err != nil {
			return nil, true, err
		}
		findings = append(findings, entries...)
	}
	return findings, true, nil
}

func runEVENT001(check checks.Check, items []map[string]any) []Finding {
	type groupedEvent struct {
		reason  string
		message string
		source  string
		count   int
	}
	grouped := map[string]*groupedEvent{}

	for _, item := range items {
		eventType := strings.TrimSpace(stringifyLookup(item, "type"))
		if eventType != "Warning" {
			continue
		}
		reason := strings.TrimSpace(stringifyLookup(item, "reason"))
		message := strings.TrimSpace(stringifyLookup(item, "message"))
		source := strings.TrimSpace(stringifyLookup(item, "source.component"))
		key := reason + "\x00" + message
		if grouped[key] == nil {
			grouped[key] = &groupedEvent{reason: reason, message: message, source: source}
		}
		grouped[key].count++
	}

	keys := make([]string, 0, len(grouped))
	for key := range grouped {
		keys = append(keys, key)
	}
	sort.Slice(keys, func(i, j int) bool {
		left := grouped[keys[i]]
		right := grouped[keys[j]]
		if left.count != right.count {
			return left.count > right.count
		}
		if left.reason != right.reason {
			return left.reason < right.reason
		}
		return left.message < right.message
	})

	findings := make([]Finding, 0, len(keys))
	for _, key := range keys {
		item := grouped[key]
		findings = append(findings, Finding{
			Namespace: "(cluster)",
			Resource:  "event-group/" + item.reason,
			Value:     fmt.Sprintf("%d", item.count),
			Message:   item.message,
		})
	}
	return findings
}

func runEVENT002(check checks.Check, items []map[string]any) []Finding {
	findings := make([]Finding, 0)
	for _, item := range items {
		if strings.TrimSpace(stringifyLookup(item, "type")) != "Warning" {
			continue
		}
		namespace := strings.TrimSpace(stringifyLookup(item, "metadata.namespace"))
		if namespace == "" {
			namespace = "default"
		}
		resource := strings.TrimSpace(stringifyLookup(item, "metadata.name"))
		if resource != "" {
			resource = "events/" + resource
		}
		findings = append(findings, Finding{
			Namespace: namespace,
			Resource:  resource,
			Value:     "Warning",
			Message:   check.FailMessage,
		})
	}
	return findings
}

func buildCompatEVENT001Items(items []map[string]any) []map[string]any {
	type groupedEvent struct {
		reason  string
		message string
		source  string
		count   int
	}
	grouped := map[string]*groupedEvent{}
	for _, item := range items {
		if strings.TrimSpace(stringifyLookup(item, "type")) != "Warning" {
			continue
		}
		reason := strings.TrimSpace(stringifyLookup(item, "reason"))
		message := strings.TrimSpace(stringifyLookup(item, "message"))
		source := strings.TrimSpace(stringifyLookup(item, "source.component"))
		key := reason + "\x00" + message
		if grouped[key] == nil {
			grouped[key] = &groupedEvent{reason: reason, message: message, source: source}
		}
		grouped[key].count++
	}
	keys := make([]string, 0, len(grouped))
	for key := range grouped {
		keys = append(keys, key)
	}
	sort.Slice(keys, func(i, j int) bool {
		left := grouped[keys[i]]
		right := grouped[keys[j]]
		if left.count != right.count {
			return left.count > right.count
		}
		if left.reason != right.reason {
			return left.reason < right.reason
		}
		return left.message < right.message
	})
	out := make([]map[string]any, 0, len(keys))
	for _, key := range keys {
		entry := grouped[key]
		out = append(out, map[string]any{
			"Reason":  entry.reason,
			"Message": entry.message,
			"Source":  entry.source,
			"Count":   entry.count,
		})
	}
	return out
}

func buildCompatEVENT002Items(items []map[string]any) []map[string]any {
	out := make([]map[string]any, 0)
	for _, item := range items {
		if strings.TrimSpace(stringifyLookup(item, "type")) != "Warning" {
			continue
		}
		out = append(out, map[string]any{
			"Timestamp": stringifyLookup(item, "metadata.creationTimestamp"),
			"Namespace": stringifyLookup(item, "metadata.namespace"),
			"Object":    strings.TrimSpace(stringifyLookup(item, "involvedObject.kind")) + "/" + strings.TrimSpace(stringifyLookup(item, "involvedObject.name")),
			"Source":    stringifyLookup(item, "source.component"),
			"Reason":    stringifyLookup(item, "reason"),
			"Message":   stringifyLookup(item, "message"),
		})
	}
	sort.Slice(out, func(i, j int) bool {
		return fmt.Sprint(out[i]["Timestamp"]) > fmt.Sprint(out[j]["Timestamp"])
	})
	return out
}

func runSEC002(check checks.Check, item map[string]any, cache map[string][]map[string]any) ([]Finding, error) {
	hostPID, _ := readBool(item, "spec.hostPID")
	hostNetwork, _ := readBool(item, "spec.hostNetwork")
	if !hostPID && !hostNetwork {
		return nil, nil
	}

	var used []string
	if hostPID {
		used = append(used, "hostPID")
	}
	if hostNetwork {
		used = append(used, "hostNetwork")
	}

	return []Finding{{
		Namespace: namespaceOf(item),
		Resource:  resourceRef("pod", item),
		Value:     fmt.Sprintf("hostPID=%t, hostNetwork=%t", hostPID, hostNetwork),
		Message:   "Pod uses " + strings.Join(used, " and "),
	}}, nil
}

func runSEC003(check checks.Check, item map[string]any, cache map[string][]map[string]any) ([]Finding, error) {
	podNamespace := namespaceOf(item)
	podResource := resourceRef("pod", item)
	podUser, podUserSet := readRunAsUser(item, "spec.securityContext.runAsUser")
	containers := appendContainerSets(item)

	var findings []Finding
	for _, container := range containers {
		name := strings.TrimSpace(stringifyLookup(container, "name"))
		containerUser, containerUserSet := readRunAsUser(container, "securityContext.runAsUser")
		isRootDefault := !containerUserSet && !podUserSet
		if (!containerUserSet || containerUser != 0) && (!podUserSet || podUser != 0) && !isRootDefault {
			continue
		}

		value := "Not Set (Defaults to root)"
		switch {
		case containerUserSet:
			value = fmt.Sprint(containerUser)
		case podUserSet:
			value = fmt.Sprint(podUser)
		}

		findings = append(findings, Finding{
			Namespace: podNamespace,
			Resource:  podResource,
			Value:     value,
			Message:   fmt.Sprintf("Container %s runs as root or has no runAsUser set", name),
		})
	}
	return findings, nil
}

func runSEC004(check checks.Check, item map[string]any, cache map[string][]map[string]any) ([]Finding, error) {
	podNamespace := namespaceOf(item)
	podResource := resourceRef("pod", item)
	containers := appendContainerSets(item)

	var findings []Finding
	for _, container := range containers {
		privileged, ok := readBool(container, "securityContext.privileged")
		if !ok || !privileged {
			continue
		}

		findings = append(findings, Finding{
			Namespace: podNamespace,
			Resource:  podResource,
			Value:     "privileged=true",
			Message:   fmt.Sprintf("Container '%s' is running in privileged mode", stringifyLookup(container, "name")),
		})
	}
	return findings, nil
}

func runSEC010(check checks.Check, item map[string]any, cache map[string][]map[string]any) ([]Finding, error) {
	podNamespace := namespaceOf(item)
	podResource := resourceRef("pod", item)
	volumes := asSlice(mustResolve(item, "spec.volumes"))

	var findings []Finding
	for _, volume := range volumes {
		volMap, ok := volume.(map[string]any)
		if !ok {
			continue
		}
		path := stringifyLookup(volMap, "hostPath.path")
		if strings.TrimSpace(path) == "" {
			continue
		}

		findings = append(findings, Finding{
			Namespace: podNamespace,
			Resource:  podResource,
			Value:     path,
			Message:   fmt.Sprintf("hostPath volume %s used", stringifyLookup(volMap, "name")),
		})
	}
	return findings, nil
}

func runSEC009(check checks.Check, item map[string]any, cache map[string][]map[string]any) ([]Finding, error) {
	podNamespace := namespaceOf(item)
	podName := strings.TrimSpace(stringifyLookup(item, "metadata.name"))
	containers := containersOnly(item)

	var findings []Finding
	for _, container := range containers {
		dropped := asSlice(mustResolve(container, "securityContext.capabilities.drop"))
		hasAll := false
		values := make([]string, 0, len(dropped))
		for _, value := range dropped {
			text := fmt.Sprint(value)
			values = append(values, text)
			if strings.EqualFold(text, "ALL") {
				hasAll = true
			}
		}
		if hasAll {
			continue
		}
		dropValue := ""
		if len(values) > 0 {
			dropValue = strings.Join(values, ",")
		}
		findings = append(findings, Finding{
			Namespace: podNamespace,
			Resource:  "pod/" + podName,
			Value:     dropValue,
			Message:   fmt.Sprintf("Container %s does not drop ALL capabilities", stringifyLookup(container, "name")),
		})
	}
	return findings, nil
}

func runSEC013(check checks.Check, item map[string]any, cache map[string][]map[string]any) ([]Finding, error) {
	podNamespace := namespaceOf(item)
	podName := strings.TrimSpace(stringifyLookup(item, "metadata.name"))
	volumes := asSlice(mustResolve(item, "spec.volumes"))

	var findings []Finding
	for _, volume := range volumes {
		volMap, ok := volume.(map[string]any)
		if !ok || mustResolve(volMap, "emptyDir") == nil {
			continue
		}
		findings = append(findings, Finding{
			Namespace: podNamespace,
			Resource:  "pod/" + podName,
			Value:     stringifyLookup(volMap, "name"),
			Message:   fmt.Sprintf("emptyDir volume %s used", stringifyLookup(volMap, "name")),
		})
	}
	return findings, nil
}

func runSEC006(check checks.Check, item map[string]any, cache map[string][]map[string]any) ([]Finding, error) {
	podNamespace := namespaceOf(item)
	podName := strings.TrimSpace(stringifyLookup(item, "metadata.name"))
	containers := containersOnly(item)

	var findings []Finding
	for _, container := range containers {
		name := strings.TrimSpace(stringifyLookup(container, "name"))
		ctx := mustResolve(container, "securityContext")
		if ctx == nil {
			findings = append(findings, Finding{
				Namespace: podNamespace,
				Resource:  "pod/" + podName,
				Value:     "Missing securityContext",
				Message:   fmt.Sprintf("Container %s has no securityContext defined", name),
			})
			continue
		}

		runAsNonRoot, hasRunAsNonRoot := readBool(container, "securityContext.runAsNonRoot")
		readOnlyRootFS, hasReadOnlyRootFS := readBool(container, "securityContext.readOnlyRootFilesystem")
		allowPrivilegeEscalation, hasAllowPrivilegeEscalation := readBool(container, "securityContext.allowPrivilegeEscalation")
		if hasRunAsNonRoot && runAsNonRoot && hasReadOnlyRootFS && readOnlyRootFS && hasAllowPrivilegeEscalation && !allowPrivilegeEscalation {
			continue
		}

		flags := []string{
			fmt.Sprintf("runAsNonRoot: %s", formatBoolPointer(hasRunAsNonRoot, runAsNonRoot)),
			fmt.Sprintf("readOnlyRootFilesystem: %s", formatBoolPointer(hasReadOnlyRootFS, readOnlyRootFS)),
			fmt.Sprintf("allowPrivilegeEscalation: %s", formatBoolPointer(hasAllowPrivilegeEscalation, allowPrivilegeEscalation)),
		}
		findings = append(findings, Finding{
			Namespace: podNamespace,
			Resource:  "pod/" + podName,
			Value:     strings.Join(flags, ", "),
			Message:   fmt.Sprintf("Container %s is missing one or more secure defaults", name),
		})
	}
	return findings, nil
}

func runSEC012(check checks.Check, item map[string]any, cache map[string][]map[string]any) ([]Finding, error) {
	podNamespace := namespaceOf(item)
	podName := strings.TrimSpace(stringifyLookup(item, "metadata.name"))
	containers := containersOnly(item)

	var findings []Finding
	for _, container := range containers {
		added := asSlice(mustResolve(container, "securityContext.capabilities.add"))
		if len(added) == 0 {
			continue
		}

		values := make([]string, 0, len(added))
		for _, value := range added {
			values = append(values, fmt.Sprint(value))
		}
		findings = append(findings, Finding{
			Namespace: podNamespace,
			Resource:  "pod/" + podName,
			Value:     strings.Join(values, ", "),
			Message:   fmt.Sprintf("Container %s adds Linux capabilities", stringifyLookup(container, "name")),
		})
	}
	return findings, nil
}

func runSEC019(check checks.Check, item map[string]any, cache map[string][]map[string]any) ([]Finding, error) {
	podNamespace := namespaceOf(item)
	podName := strings.TrimSpace(stringifyLookup(item, "metadata.name"))

	var findings []Finding
	if annotations, ok := mustResolve(item, "metadata.annotations").(map[string]any); ok {
		for key, raw := range annotations {
			if !strings.HasPrefix(key, "container.apparmor.security.beta.kubernetes.io/") {
				continue
			}
			value := strings.TrimSpace(fmt.Sprint(raw))
			if value == "" || value == "runtime/default" || strings.HasPrefix(value, "localhost/") {
				continue
			}
			findings = append(findings, Finding{
				Namespace: podNamespace,
				Resource:  "pod/" + podName,
				Value:     value,
				Message:   fmt.Sprintf("Unsupported AppArmor annotation value on %s", key),
			})
		}
	}

	containers := allContainers(item)
	for _, container := range containers {
		profileType := strings.TrimSpace(stringifyLookup(container, "securityContext.appArmorProfile.type"))
		if profileType == "" || profileType == "RuntimeDefault" || profileType == "Localhost" {
			continue
		}
		findings = append(findings, Finding{
			Namespace: podNamespace,
			Resource:  "pod/" + podName,
			Value:     profileType,
			Message:   fmt.Sprintf("Container %s uses unsupported AppArmor profile type", stringifyLookup(container, "name")),
		})
	}
	return findings, nil
}

func runSEC020(check checks.Check, item map[string]any, cache map[string][]map[string]any) ([]Finding, error) {
	podNamespace := namespaceOf(item)
	podName := strings.TrimSpace(stringifyLookup(item, "metadata.name"))
	podSeccomp := strings.TrimSpace(stringifyLookup(item, "spec.securityContext.seccompProfile.type"))
	containers := allContainers(item)

	var findings []Finding
	for _, container := range containers {
		containerSeccomp := strings.TrimSpace(stringifyLookup(container, "securityContext.seccompProfile.type"))
		if containerSeccomp != "" || podSeccomp != "" {
			continue
		}
		findings = append(findings, Finding{
			Namespace: podNamespace,
			Resource:  "pod/" + podName,
			Value:     "",
			Message:   fmt.Sprintf("Container %s has no explicit seccomp profile", stringifyLookup(container, "name")),
		})
	}
	return findings, nil
}

func runSEC001(check checks.Check, item map[string]any, cache map[string][]map[string]any) ([]Finding, error) {
	name := stringifyLookup(item, "metadata.name")
	switch {
	case strings.HasPrefix(name, "sh.helm.release.v1."):
		return nil, nil
	case strings.HasPrefix(name, "bootstrap-token-"):
		return nil, nil
	case strings.HasPrefix(name, "default-token-"):
		return nil, nil
	case name == "kube-root-ca.crt":
		return nil, nil
	}
	used, err := usedSecrets(cache)
	if err != nil {
		return nil, err
	}
	if used[namespaceOf(item)+"/"+name] || used["*/"+name] {
		return nil, nil
	}
	return []Finding{{Namespace: namespaceOf(item), Resource: "secret/" + name, Value: name, Message: "Secret appears unused across workloads, ingresses, service accounts, or CRs"}}, nil
}

func runSEC005(check checks.Check, item map[string]any, cache map[string][]map[string]any) ([]Finding, error) {
	hostIPC, _ := readBool(item, "spec.hostIPC")
	if !hostIPC {
		return nil, nil
	}
	return []Finding{{Namespace: namespaceOf(item), Resource: "pod/" + stringifyLookup(item, "metadata.name"), Value: "true", Message: "hostIPC is enabled"}}, nil
}

func runSEC007(check checks.Check, item map[string]any, cache map[string][]map[string]any) ([]Finding, error) {
	labels, _ := mustResolve(item, "metadata.labels").(map[string]any)
	enforce := fmt.Sprint(labels["pod-security.kubernetes.io/enforce"])
	warn := fmt.Sprint(labels["pod-security.kubernetes.io/warn"])
	audit := fmt.Sprint(labels["pod-security.kubernetes.io/audit"])
	if enforce != "" && enforce != "<nil>" {
		return nil, nil
	}
	issue := "No pod security labels"
	if (warn != "" && warn != "<nil>") || (audit != "" && audit != "<nil>") {
		issue = "warn/audit set without enforce"
	}
	return []Finding{{Namespace: stringifyLookup(item, "metadata.name"), Resource: "namespace/" + stringifyLookup(item, "metadata.name"), Value: "", Message: issue}}, nil
}

func runSEC008(check checks.Check, item map[string]any, cache map[string][]map[string]any) ([]Finding, error) {
	var findings []Finding
	for _, container := range allContainers(item) {
		for _, env := range asSlice(mustResolve(container, "env")) {
			secretName := stringifyLookup(env, "valueFrom.secretKeyRef.name")
			if secretName == "" {
				continue
			}
			findings = append(findings, Finding{
				Namespace: namespaceOf(item),
				Resource:  "pod/" + stringifyLookup(item, "metadata.name"),
				Value:     "env: " + stringifyLookup(env, "name"),
				Message:   fmt.Sprintf("Secret %s exposed via env var in container %s", secretName, stringifyLookup(container, "name")),
			})
		}
	}
	return findings, nil
}

func runSEC011(check checks.Check, item map[string]any, cache map[string][]map[string]any) ([]Finding, error) {
	var findings []Finding
	for _, container := range containersOnly(item) {
		if asInt64(mustResolve(container, "securityContext.runAsUser")) != 0 {
			continue
		}
		findings = append(findings, Finding{
			Namespace: namespaceOf(item),
			Resource:  "pod/" + stringifyLookup(item, "metadata.name"),
			Value:     "0",
			Message:   fmt.Sprintf("Container %s runs as UID 0", stringifyLookup(container, "name")),
		})
	}
	return findings, nil
}

func runSEC014(check checks.Check, item map[string]any, cache map[string][]map[string]any) ([]Finding, error) {
	trusted := append([]string(nil), currentRuntime.TrustedRegistries...)
	if len(trusted) == 0 {
		trusted = []string{"mcr.microsoft.com/"}
	}
	var findings []Finding
	for _, container := range containersOnly(item) {
		image := stringifyLookup(container, "image")
		ok := false
		for _, prefix := range trusted {
			if strings.HasPrefix(image, prefix) {
				ok = true
				break
			}
		}
		if ok {
			continue
		}
		findings = append(findings, Finding{
			Namespace: namespaceOf(item),
			Resource:  "pod/" + stringifyLookup(item, "metadata.name"),
			Value:     image,
			Message:   fmt.Sprintf("Image from untrusted registry in container %s", stringifyLookup(container, "name")),
		})
	}
	return findings, nil
}

func runSEC016(check checks.Check, item map[string]any, cache map[string][]map[string]any) ([]Finding, error) {
	podName := stringifyLookup(item, "metadata.name")
	var findings []Finding
	if stringifyLookup(item, "spec.securityContext.seccompProfile.type") == "Unconfined" {
		findings = append(findings, Finding{
			Namespace: namespaceOf(item),
			Resource:  "pod/" + podName,
			Value:     "Unconfined",
			Message:   "Pod seccomp profile is Unconfined",
		})
	}
	for _, container := range allContainers(item) {
		if stringifyLookup(container, "securityContext.seccompProfile.type") != "Unconfined" {
			continue
		}
		findings = append(findings, Finding{
			Namespace: namespaceOf(item),
			Resource:  "pod/" + podName,
			Value:     "Unconfined",
			Message:   fmt.Sprintf("Container %s seccomp profile is Unconfined", stringifyLookup(container, "name")),
		})
	}
	return findings, nil
}

func runSEC017(check checks.Check, item map[string]any, cache map[string][]map[string]any) ([]Finding, error) {
	podName := stringifyLookup(item, "metadata.name")
	var findings []Finding
	for _, container := range allContainers(item) {
		procMount := stringifyLookup(container, "securityContext.procMount")
		if procMount == "" || procMount == "Default" {
			continue
		}
		findings = append(findings, Finding{
			Namespace: namespaceOf(item),
			Resource:  "pod/" + podName,
			Value:     procMount,
			Message:   fmt.Sprintf("Container %s procMount must be Default or omitted", stringifyLookup(container, "name")),
		})
	}
	return findings, nil
}

func runNODE001(check checks.Check, item map[string]any, cache map[string][]map[string]any) ([]Finding, error) {
	name := stringifyLookup(item, "metadata.name")
	readyTrue := false
	var issues []string
	for _, c := range asSlice(mustResolve(item, "status.conditions")) {
		typ := stringifyLookup(c, "type")
		status := stringifyLookup(c, "status")
		if typ == "Ready" && status == "True" {
			readyTrue = true
		}
		if typ != "Ready" && status != "False" {
			issues = append(issues, typ+": "+stringifyLookup(c, "message"))
		}
	}
	if readyTrue {
		return nil, nil
	}
	message := "Unknown Issue"
	if len(issues) > 0 {
		message = strings.Join(issues, " | ")
	}
	return []Finding{{Namespace: "(cluster)", Resource: "node/" + name, Value: "❌ Not Ready", Message: message}}, nil
}

func runNODE002(check checks.Check, item map[string]any, cache map[string][]map[string]any) ([]Finding, error) {
	if stringifyLookup(item, "metadata.name") != "" {
		return nil, nil
	}
	nodes, err := getCachedItems(cache, "nodes")
	if err != nil {
		return nil, err
	}
	topByNode, err := parseTopNodes()
	if err != nil {
		return nil, nil
	}
	var findings []Finding
	for _, node := range nodes {
		if !nodeReady(node) {
			continue
		}
		name := stringifyLookup(node, "metadata.name")
		top, ok := topByNode[name]
		if !ok {
			continue
		}
		var issues []string
		if top.CPUPct > 75 {
			issues = append(issues, fmt.Sprintf("CPU %.2f%%", top.CPUPct))
		} else if top.CPUPct > 50 {
			issues = append(issues, fmt.Sprintf("CPU %.2f%%", top.CPUPct))
		}
		if top.MemPct > 75 {
			issues = append(issues, fmt.Sprintf("Memory %.2f%%", top.MemPct))
		} else if top.MemPct > 50 {
			issues = append(issues, fmt.Sprintf("Memory %.2f%%", top.MemPct))
		}
		if top.DiskPct > 80 {
			issues = append(issues, fmt.Sprintf("Disk %.2f%%", top.DiskPct))
		} else if top.DiskPct > 60 {
			issues = append(issues, fmt.Sprintf("Disk %.2f%%", top.DiskPct))
		}
		if len(issues) == 0 {
			continue
		}
		findings = append(findings, Finding{Namespace: "(cluster)", Resource: "node/" + name, Value: strings.Join(issues, ", "), Message: "Node resource pressure detected"})
	}
	return findings, nil
}

func runNODE003(check checks.Check, item map[string]any, cache map[string][]map[string]any) ([]Finding, error) {
	pods, err := getCachedItems(cache, "pods")
	if err != nil {
		return nil, err
	}
	if len(currentRuntime.Excluded) > 0 {
		if currentRuntime.KubeClient != nil {
			allPods, err := currentRuntime.KubeClient.List(currentRuntime.KubeContext, "pods", true)
			if err == nil {
				pods = allPods
			}
		}
	}
	name := stringifyLookup(item, "metadata.name")
	capacity := asInt64(mustResolve(item, "status.capacity.pods"))
	if capacity == 0 {
		return nil, nil
	}
	count := int64(0)
	for _, pod := range pods {
		if stringifyLookup(pod, "spec.nodeName") == name {
			count++
		}
	}
	pct := float64(count) / float64(capacity) * 100
	if pct < 80 {
		return nil, nil
	}
	status := "Warning"
	if pct >= 90 {
		status = "Critical"
	}
	return []Finding{{Namespace: "(cluster)", Resource: "node/" + name, Value: fmt.Sprintf("%.2f%%", pct), Message: status}}, nil
}

func runNET001(check checks.Check, item map[string]any, cache map[string][]map[string]any) ([]Finding, error) {
	if stringifyLookup(item, "spec.type") == "ExternalName" {
		return nil, nil
	}
	ns := namespaceOf(item)
	name := stringifyLookup(item, "metadata.name")
	epSlices, _ := getCachedItems(cache, "endpointslices")
	endpoints, _ := getCachedItems(cache, "endpoints")
	for _, slice := range epSlices {
		if namespaceOf(slice) == ns && stringifyLookup(slice, "metadata.labels.kubernetes.io/service-name") == name {
			return nil, nil
		}
	}
	for _, ep := range endpoints {
		if namespaceOf(ep) == ns && stringifyLookup(ep, "metadata.name") == name && len(asSlice(mustResolve(ep, "subsets"))) > 0 {
			return nil, nil
		}
	}
	return []Finding{{Namespace: ns, Resource: "service/" + name, Value: "", Message: "No endpoints or endpoint slices"}}, nil
}

func runNET002(check checks.Check, item map[string]any, cache map[string][]map[string]any) ([]Finding, error) {
	typ := stringifyLookup(item, "spec.type")
	if typ != "LoadBalancer" && typ != "NodePort" {
		return nil, nil
	}
	var external []string
	for _, entry := range asSlice(mustResolve(item, "status.loadBalancer.ingress")) {
		ip := stringifyLookup(entry, "ip")
		host := stringifyLookup(entry, "hostname")
		if ip != "" && !isInternalIP(ip) {
			external = append(external, ip)
		} else if host != "" {
			external = append(external, host)
		}
	}
	if typ != "NodePort" && len(external) == 0 {
		return nil, nil
	}
	msg := "Exposed via NodePort"
	if len(external) > 0 {
		msg = "Exposed via external IP: " + strings.Join(external, ", ")
	}
	return []Finding{{Namespace: namespaceOf(item), Resource: "service/" + stringifyLookup(item, "metadata.name"), Value: typ, Message: msg}}, nil
}

func runNET003(check checks.Check, item map[string]any, cache map[string][]map[string]any) ([]Finding, error) {
	services, err := getCachedItems(cache, "services")
	if err != nil {
		return nil, err
	}
	secrets, err := getCachedItems(cache, "secrets")
	if err != nil {
		return nil, err
	}
	ns := namespaceOf(item)
	name := stringifyLookup(item, "metadata.name")
	var findings []Finding
	if stringifyLookup(item, "spec.ingressClassName") == "" && stringifyLookup(item, "metadata.annotations.kubernetes.io/ingress.class") == "" {
		findings = append(findings, Finding{Namespace: ns, Resource: "ingress/" + name, Value: "-", Message: "Missing ingress class"})
	}
	for _, tls := range asSlice(mustResolve(item, "spec.tls")) {
		secretName := stringifyLookup(tls, "secretName")
		if secretName != "" && !secretExists(secrets, ns, secretName) {
			findings = append(findings, Finding{Namespace: ns, Resource: "ingress/" + name, Value: secretName, Message: "TLS secret not found"})
		}
	}
	rules := asSlice(mustResolve(item, "spec.rules"))
	if len(rules) == 0 {
		if mustResolve(item, "spec.defaultBackend") == nil {
			findings = append(findings, Finding{Namespace: ns, Resource: "ingress/" + name, Value: "-", Message: "No rules or default backend"})
			return findings, nil
		}
		svcName := stringifyLookup(item, "spec.defaultBackend.service.name")
		port := stringifyLookup(item, "spec.defaultBackend.service.port.number")
		svc := serviceByName(services, ns, svcName)
		if svc == nil {
			findings = append(findings, Finding{Namespace: ns, Resource: "ingress/" + name, Value: svcName, Message: "Default backend service not found"})
		} else if stringifyLookup(svc, "spec.type") != "ExternalName" && !serviceHasPort(svc, port) {
			findings = append(findings, Finding{Namespace: ns, Resource: "ingress/" + name, Value: svcName + ":" + port, Message: "Backend port missing"})
		}
		return findings, nil
	}
	hostPathMap := map[string]string{}
	for _, rule := range rules {
		hostName := stringifyLookup(rule, "host")
		if hostName == "" {
			hostName = "N/A"
		}
		for _, path := range asSlice(mustResolve(rule, "http.paths")) {
			pathValue := stringifyLookup(path, "path")
			key := ns + "|" + hostName + "|" + pathValue
			if conflict, ok := hostPathMap[key]; ok {
				findings = append(findings, Finding{Namespace: ns, Resource: "ingress/" + name, Value: hostName + pathValue, Message: "Duplicate host/path (conflicts with ingress " + conflict + ")"})
			} else {
				hostPathMap[key] = name
			}
			pathType := stringifyLookup(path, "pathType")
			if pathType != "" && pathType != "Exact" && pathType != "Prefix" && pathType != "ImplementationSpecific" {
				findings = append(findings, Finding{Namespace: ns, Resource: "ingress/" + name, Value: pathType, Message: "Invalid pathType"})
			}
			svcName := stringifyLookup(path, "backend.service.name")
			port := stringifyLookup(path, "backend.service.port.number")
			svc := serviceByName(services, ns, svcName)
			if svc == nil {
				findings = append(findings, Finding{Namespace: ns, Resource: "ingress/" + name, Value: svcName, Message: "Service not found"})
			} else if stringifyLookup(svc, "spec.type") != "ExternalName" && !serviceHasPort(svc, port) {
				findings = append(findings, Finding{Namespace: ns, Resource: "ingress/" + name, Value: svcName + ":" + port, Message: "Service missing port"})
			}
		}
	}
	return findings, nil
}

func runNET004(check checks.Check, item map[string]any, cache map[string][]map[string]any) ([]Finding, error) {
	if stringifyLookup(item, "metadata.name") != "" {
		return nil, nil
	}
	namespaces, err := getCachedItems(cache, "namespaces")
	if err != nil {
		return nil, err
	}
	policies, err := getCachedItems(cache, "networkpolicies")
	if err != nil {
		return nil, err
	}
	pods, err := getCachedItems(cache, "pods")
	if err != nil {
		return nil, err
	}
	var findings []Finding
	for _, ns := range namespaces {
		name := stringifyLookup(ns, "metadata.name")
		activePods := 0
		for _, pod := range pods {
			if namespaceOf(pod) == name {
				activePods++
			}
		}
		if activePods == 0 {
			continue
		}
		found := false
		for _, np := range policies {
			if namespaceOf(np) == name {
				found = true
				break
			}
		}
		if !found {
			findings = append(findings, Finding{Namespace: name, Resource: "namespace/" + name, Value: "", Message: "No NetworkPolicy in active namespace"})
		}
	}
	return findings, nil
}

func runNET005(check checks.Check, item map[string]any, cache map[string][]map[string]any) ([]Finding, error) {
	ingresses, err := getCachedItems(cache, "ingresses")
	if err != nil {
		return nil, err
	}
	ns := namespaceOf(item)
	name := stringifyLookup(item, "metadata.name")
	hostPathMap := map[string]string{}
	for _, ingress := range ingresses {
		if namespaceOf(ingress) != ns {
			continue
		}
		ingressName := stringifyLookup(ingress, "metadata.name")
		for _, rule := range asSlice(mustResolve(ingress, "spec.rules")) {
			hostName := stringifyLookup(rule, "host")
			if hostName == "" {
				hostName = "*"
			}
			for _, path := range asSlice(mustResolve(rule, "http.paths")) {
				fullPath := stringifyLookup(path, "path")
				if fullPath == "" {
					fullPath = "/"
				}
				key := hostName + "|" + fullPath
				if existing, ok := hostPathMap[key]; ok && ingressName == name {
					return []Finding{{Namespace: ns, Resource: "ingress/" + name, Value: hostName + fullPath, Message: "Duplicate host/path combination found with ingress/" + existing}}, nil
				}
				hostPathMap[key] = ingressName
			}
		}
	}
	return nil, nil
}

func runNET006(check checks.Check, item map[string]any, cache map[string][]map[string]any) ([]Finding, error) {
	var findings []Finding
	for _, rule := range asSlice(mustResolve(item, "spec.rules")) {
		host := stringifyLookup(rule, "host")
		if strings.Contains(host, "*") {
			findings = append(findings, Finding{Namespace: namespaceOf(item), Resource: "ingress/" + stringifyLookup(item, "metadata.name"), Value: host, Message: "Ingress uses wildcard host"})
		}
	}
	return findings, nil
}

func runNET007(check checks.Check, item map[string]any, cache map[string][]map[string]any) ([]Finding, error) {
	if stringifyLookup(item, "spec.type") == "ExternalName" {
		return nil, nil
	}
	selector := mustResolve(item, "spec.selector")
	if selector == nil {
		return nil, nil
	}
	pods, err := getCachedItems(cache, "pods")
	if err != nil {
		return nil, err
	}
	ns := namespaceOf(item)
	var matchingPods []map[string]any
	for _, pod := range pods {
		if namespaceOf(pod) == ns && stringifyLookup(pod, "status.phase") == "Running" && selectorMatchesLabels(selector, mustResolve(pod, "metadata.labels")) {
			matchingPods = append(matchingPods, pod)
		}
	}
	if len(matchingPods) == 0 {
		return nil, nil
	}
	var findings []Finding
	for _, portMapping := range asSlice(mustResolve(item, "spec.ports")) {
		targetPort := stringifyLookup(portMapping, "targetPort")
		if targetPort == "" {
			targetPort = stringifyLookup(portMapping, "port")
		}
		if serviceTargetPortMatchesPods(targetPort, matchingPods) {
			continue
		}
		findings = append(findings, Finding{Namespace: ns, Resource: "service/" + stringifyLookup(item, "metadata.name"), Value: targetPort, Message: "Service targetPort '" + targetPort + "' not found in backing pods"})
	}
	return findings, nil
}

func runNET008(check checks.Check, item map[string]any, cache map[string][]map[string]any) ([]Finding, error) {
	if stringifyLookup(item, "spec.type") != "ExternalName" {
		return nil, nil
	}
	target := stringifyLookup(item, "spec.externalName")
	if !looksLikeIPv4(target) || !isInternalIP(target) {
		return nil, nil
	}
	return []Finding{{Namespace: namespaceOf(item), Resource: "service/" + stringifyLookup(item, "metadata.name"), Value: target, Message: "ExternalName service points to internal IP address"}}, nil
}

func runNET009(check checks.Check, item map[string]any, cache map[string][]map[string]any) ([]Finding, error) {
	isPermissive := false
	var parts []string
	policyTypes := asSlice(mustResolve(item, "spec.policyTypes"))
	if containsString(policyTypes, "Ingress") && len(asSlice(mustResolve(item, "spec.ingress"))) == 0 {
		isPermissive = true
		parts = append(parts, "Allows all Ingress traffic (empty ingress rules).")
	}
	if containsString(policyTypes, "Egress") && len(asSlice(mustResolve(item, "spec.egress"))) == 0 {
		isPermissive = true
		parts = append(parts, "Allows all Egress traffic (empty egress rules).")
	}
	for _, rule := range asSlice(mustResolve(item, "spec.ingress")) {
		for _, from := range asSlice(mustResolve(rule, "from")) {
			if stringifyLookup(from, "ipBlock.cidr") == "0.0.0.0/0" {
				isPermissive = true
				parts = append(parts, "Ingress rule contains '0.0.0.0/0' ipBlock.")
			}
		}
	}
	for _, rule := range asSlice(mustResolve(item, "spec.egress")) {
		for _, to := range asSlice(mustResolve(rule, "to")) {
			if stringifyLookup(to, "ipBlock.cidr") == "0.0.0.0/0" {
				isPermissive = true
				parts = append(parts, "Egress rule contains '0.0.0.0/0' ipBlock.")
			}
		}
	}
	if !isPermissive {
		return nil, nil
	}
	return []Finding{{Namespace: namespaceOf(item), Resource: "networkpolicy/" + stringifyLookup(item, "metadata.name"), Value: joinAny(policyTypes, ", "), Message: strings.Join(parts, " ")}}, nil
}

func runNET010(check checks.Check, item map[string]any, cache map[string][]map[string]any) ([]Finding, error) {
	var details []string
	for _, rule := range asSlice(mustResolve(item, "spec.ingress")) {
		for _, from := range asSlice(mustResolve(rule, "from")) {
			if stringifyLookup(from, "ipBlock.cidr") == "0.0.0.0/0" {
				details = append(details, "Ingress rule allows '0.0.0.0/0' (all IPs)")
			}
		}
	}
	for _, rule := range asSlice(mustResolve(item, "spec.egress")) {
		for _, to := range asSlice(mustResolve(rule, "to")) {
			if stringifyLookup(to, "ipBlock.cidr") == "0.0.0.0/0" {
				details = append(details, "Egress rule allows '0.0.0.0/0' (all IPs)")
			}
		}
	}
	if len(details) == 0 {
		return nil, nil
	}
	return []Finding{{Namespace: namespaceOf(item), Resource: "networkpolicy/" + stringifyLookup(item, "metadata.name"), Value: "0.0.0.0/0", Message: strings.Join(details, "; ")}}, nil
}

func runNET011(check checks.Check, item map[string]any, cache map[string][]map[string]any) ([]Finding, error) {
	if len(asSlice(mustResolve(item, "spec.policyTypes"))) > 0 {
		return nil, nil
	}
	return []Finding{{Namespace: namespaceOf(item), Resource: "networkpolicy/" + stringifyLookup(item, "metadata.name"), Value: "N/A", Message: "PolicyTypes field is missing or empty"}}, nil
}

func runNET012(check checks.Check, item map[string]any, cache map[string][]map[string]any) ([]Finding, error) {
	hostNetwork, _ := readBool(item, "spec.hostNetwork")
	if !hostNetwork {
		return nil, nil
	}
	return []Finding{{Namespace: namespaceOf(item), Resource: "pod/" + stringifyLookup(item, "metadata.name"), Value: "true", Message: "hostNetwork is enabled"}}, nil
}

func runNET013(check checks.Check, item map[string]any, cache map[string][]map[string]any) ([]Finding, error) {
	if stringifyLookup(item, "metadata.name") != "" {
		return nil, nil
	}
	ingresses, err := getCachedItems(cache, "ingresses")
	if err != nil {
		return nil, err
	}
	if len(ingresses) == 0 {
		return nil, nil
	}
	gatewayClasses, _ := getCachedItems(cache, "gatewayclasses.gateway.networking.k8s.io")
	gateways, _ := getCachedItems(cache, "gateways.gateway.networking.k8s.io")
	httpRoutes, _ := getCachedItems(cache, "httproutes.gateway.networking.k8s.io")
	if len(gatewayClasses) > 0 || len(gateways) > 0 || len(httpRoutes) > 0 {
		return nil, nil
	}
	return []Finding{{
		Namespace: "(cluster)",
		Resource:  "gateway-api/adoption",
		Value:     fmt.Sprintf("ingresses=%d", len(ingresses)),
		Message:   "Ingress is in use but Gateway API resources are not yet adopted.",
	}}, nil
}

func runNET014(check checks.Check, item map[string]any, cache map[string][]map[string]any) ([]Finding, error) {
	ns := namespaceOf(item)
	name := stringifyLookup(item, "metadata.name")
	parents := asSlice(mustResolve(item, "spec.parentRefs"))
	if len(parents) == 0 {
		return []Finding{{Namespace: ns, Resource: "httproute/" + name, Value: "-", Message: "No parentRefs defined"}}, nil
	}
	accepted := false
	for _, parent := range asSlice(mustResolve(item, "status.parents")) {
		for _, condition := range asSlice(mustResolve(parent, "conditions")) {
			if stringifyLookup(condition, "type") == "Accepted" && strings.EqualFold(stringifyLookup(condition, "status"), "true") {
				accepted = true
				break
			}
		}
		if accepted {
			break
		}
	}
	if accepted {
		return nil, nil
	}
	parentList := make([]string, 0, len(parents))
	for _, p := range parents {
		pns := stringifyLookup(p, "namespace")
		if pns == "" {
			pns = ns
		}
		parentList = append(parentList, pns+"/"+stringifyLookup(p, "name"))
	}
	return []Finding{{Namespace: ns, Resource: "httproute/" + name, Value: strings.Join(parentList, ", "), Message: "Route is not Accepted by any parent Gateway"}}, nil
}

func runNET015(check checks.Check, item map[string]any, cache map[string][]map[string]any) ([]Finding, error) {
	httpRoutes, err := getCachedItems(cache, "httproutes.gateway.networking.k8s.io")
	if err != nil {
		return nil, err
	}
	gwNs := namespaceOf(item)
	gwName := stringifyLookup(item, "metadata.name")
	attachedCount := 0
	for _, route := range httpRoutes {
		rns := namespaceOf(route)
		for _, p := range asSlice(mustResolve(route, "spec.parentRefs")) {
			kind := stringifyLookup(p, "kind")
			if kind == "" {
				kind = "Gateway"
			}
			if kind != "Gateway" {
				continue
			}
			targetNs := stringifyLookup(p, "namespace")
			if targetNs == "" {
				targetNs = rns
			}
			if targetNs == gwNs && stringifyLookup(p, "name") == gwName {
				attachedCount++
				break
			}
		}
	}
	if attachedCount > 0 {
		return nil, nil
	}
	return []Finding{{Namespace: gwNs, Resource: "gateway/" + gwName, Value: "0", Message: "Gateway has no attached HTTPRoutes"}}, nil
}

func runNET016(check checks.Check, item map[string]any, cache map[string][]map[string]any) ([]Finding, error) {
	name := stringifyLookup(item, "metadata.name")
	ns := namespaceOf(item)
	var findings []Finding
	for _, conditionName := range []string{"Accepted", "Programmed"} {
		condition := findCondition(asSlice(mustResolve(item, "status.conditions")), conditionName)
		if condition == nil {
			continue
		}
		if strings.EqualFold(stringifyLookup(condition, "status"), "true") {
			continue
		}
		msg := stringifyLookup(condition, "reason")
		if detail := stringifyLookup(condition, "message"); detail != "" {
			if msg != "" {
				msg += ": "
			}
			msg += detail
		}
		if msg == "" {
			msg = strings.ToLower(conditionName) + " condition is not healthy"
		}
		findings = append(findings, Finding{Namespace: ns, Resource: "gateway/" + name, Value: conditionName, Message: msg})
	}
	return findings, nil
}

func runNET017(check checks.Check, item map[string]any, cache map[string][]map[string]any) ([]Finding, error) {
	referenceGrants, _ := getCachedItems(cache, "referencegrants.gateway.networking.k8s.io")
	secrets, err := getCachedItems(cache, "secrets")
	if err != nil {
		return nil, err
	}
	gwNs := namespaceOf(item)
	gwName := stringifyLookup(item, "metadata.name")
	var findings []Finding
	for _, listener := range asSlice(mustResolve(item, "spec.listeners")) {
		listenerName := stringifyLookup(listener, "name")
		if listenerName == "" {
			listenerName = "<unnamed>"
		}
		for _, certRef := range asSlice(mustResolve(listener, "tls.certificateRefs")) {
			kind := stringifyLookup(certRef, "kind")
			if kind == "" {
				kind = "Secret"
			}
			group := stringifyLookup(certRef, "group")
			if kind != "Secret" || group != "" {
				continue
			}
			secretName := stringifyLookup(certRef, "name")
			if secretName == "" {
				continue
			}
			secretNs := stringifyLookup(certRef, "namespace")
			if secretNs == "" {
				secretNs = gwNs
			}
			if !secretExists(secrets, secretNs, secretName) {
				findings = append(findings, Finding{Namespace: gwNs, Resource: "gateway/" + gwName, Value: secretNs + "/" + secretName, Message: "TLS Secret not found for listener " + listenerName})
				continue
			}
			if secretNs != gwNs && !hasReferenceGrant(referenceGrants, gwNs, secretNs, secretName) {
				findings = append(findings, Finding{Namespace: gwNs, Resource: "gateway/" + gwName, Value: secretNs + "/" + secretName, Message: "Cross-namespace Secret reference missing required ReferenceGrant for listener " + listenerName})
			}
		}
	}
	return findings, nil
}

func runNET018(check checks.Check, item map[string]any, cache map[string][]map[string]any) ([]Finding, error) {
	if stringifyLookup(item, "metadata.name") != "" {
		return nil, nil
	}
	services, err := getCachedItems(cache, "services")
	if err != nil {
		return nil, err
	}
	grouped := map[string][]map[string]any{}
	for _, svc := range services {
		if stringifyLookup(svc, "spec.type") == "ExternalName" {
			continue
		}
		selector := selectorKey(mustResolve(svc, "spec.selector"))
		if selector == "" {
			continue
		}
		key := namespaceOf(svc) + "|" + selector
		grouped[key] = append(grouped[key], svc)
	}
	var findings []Finding
	for _, items := range grouped {
		if len(items) < 2 {
			continue
		}
		names := make([]string, 0, len(items))
		for _, svc := range items {
			names = append(names, stringifyLookup(svc, "metadata.name"))
		}
		sort.Strings(names)
		for _, svc := range items {
			findings = append(findings, Finding{
				Namespace: namespaceOf(svc),
				Resource:  "service/" + stringifyLookup(svc, "metadata.name"),
				Value:     selectorJSON(mustResolve(svc, "spec.selector")),
				Message:   "Service shares its selector with: " + strings.Join(names, ", "),
			})
		}
	}
	return findings, nil
}

func runPV001(check checks.Check, item map[string]any, cache map[string][]map[string]any) ([]Finding, error) {
	if stringifyLookup(item, "status.phase") == "Bound" {
		return nil, nil
	}
	pvcs, err := getCachedItems(cache, "persistentvolumeclaims")
	if err != nil {
		return nil, err
	}
	name := stringifyLookup(item, "metadata.name")
	for _, pvc := range pvcs {
		if stringifyLookup(pvc, "spec.volumeName") == name {
			return nil, nil
		}
	}
	return []Finding{{Namespace: "(cluster)", Resource: "pv/" + name, Value: stringifyLookup(item, "spec.capacity.storage"), Message: "PV is not bound to any PVC"}}, nil
}

func runPVC001(check checks.Check, item map[string]any, cache map[string][]map[string]any) ([]Finding, error) {
	pods, err := getCachedItems(cache, "pods")
	if err != nil {
		return nil, err
	}
	ns := namespaceOf(item)
	name := stringifyLookup(item, "metadata.name")
	for _, pod := range pods {
		if namespaceOf(pod) != ns {
			continue
		}
		for _, volume := range asSlice(mustResolve(pod, "spec.volumes")) {
			if stringifyLookup(volume, "persistentVolumeClaim.claimName") == name {
				return nil, nil
			}
		}
	}
	return []Finding{{Namespace: ns, Resource: "pvc/" + name, Value: stringifyLookup(item, "spec.resources.requests.storage"), Message: "PVC is not used by any running pod"}}, nil
}

func runPVC003(check checks.Check, item map[string]any, cache map[string][]map[string]any) ([]Finding, error) {
	if !containsString(asSlice(mustResolve(item, "spec.accessModes")), "ReadWriteMany") {
		return nil, nil
	}
	storageClassName := stringifyLookup(item, "spec.storageClassName")
	if storageClassName == "" {
		return []Finding{{Namespace: namespaceOf(item), Resource: "pvc/" + stringifyLookup(item, "metadata.name"), Value: joinAny(asSlice(mustResolve(item, "spec.accessModes")), ", "), Message: "PVC requests ReadWriteMany access mode but uses default StorageClass (potential block storage)."}}, nil
	}
	storageClasses, err := getCachedItems(cache, "storageclasses")
	if err != nil {
		return nil, err
	}
	blockProvisioners := map[string]bool{
		"kubernetes.io/aws-ebs": true, "ebs.csi.aws.com": true,
		"kubernetes.io/gce-pd": true, "pd.csi.storage.gke.io": true,
		"kubernetes.io/azure-disk": true, "disk.csi.azure.com": true,
		"kubernetes.io/cinder": true, "cinder.csi.openstack.org": true,
		"kubernetes.io/portworx-volume": true, "rancher.io/local-path": true,
	}
	for _, sc := range storageClasses {
		if stringifyLookup(sc, "metadata.name") == storageClassName && blockProvisioners[stringifyLookup(sc, "provisioner")] {
			return []Finding{{Namespace: namespaceOf(item), Resource: "pvc/" + stringifyLookup(item, "metadata.name"), Value: "Access Modes: " + joinAny(asSlice(mustResolve(item, "spec.accessModes")), ", ") + ", Provisioner: " + stringifyLookup(sc, "provisioner"), Message: "PVC requests ReadWriteMany access mode, but StorageClass '" + stringifyLookup(sc, "provisioner") + "' is typically for block storage."}}, nil
		}
	}
	return nil, nil
}

func runSC002AKS(check checks.Check, item map[string]any, cache map[string][]map[string]any) ([]Finding, error) {
	p := stringifyLookup(item, "provisioner")
	if p != "kubernetes.io/azure-disk" && p != "kubernetes.io/azure-file" {
		return nil, nil
	}
	return []Finding{{Namespace: "(cluster)", Resource: "storageclass/" + stringifyLookup(item, "metadata.name"), Value: p, Message: "Azure in-tree provisioner is not AKS Automatic compatible"}}, nil
}

func runSC002Expansion(check checks.Check, item map[string]any, cache map[string][]map[string]any) ([]Finding, error) {
	if value, ok := readBool(item, "allowVolumeExpansion"); ok && value {
		return nil, nil
	}
	return []Finding{{Namespace: "(cluster)", Resource: "storageclass/" + stringifyLookup(item, "metadata.name"), Value: "", Message: "StorageClass does not allow volume expansion."}}, nil
}

func runSC003(check checks.Check, item map[string]any, cache map[string][]map[string]any) ([]Finding, error) {
	if stringifyLookup(item, "metadata.name") != "" {
		return nil, nil
	}
	topByNode, err := parseTopNodes()
	if err != nil {
		return nil, nil
	}
	if len(topByNode) == 0 {
		return nil, nil
	}
	var sum float64
	var count float64
	for _, top := range topByNode {
		if top.DiskPct <= 0 {
			continue
		}
		sum += top.DiskPct
		count++
	}
	if count == 0 {
		return nil, nil
	}
	avg := sum / count
	if avg <= 80 {
		return nil, nil
	}
	return []Finding{{Namespace: "(cluster)", Resource: "cluster/storage", Value: fmt.Sprintf("%.2f%%", avg), Message: "Cluster storage usage is above recommended threshold."}}, nil
}

func runPROM006(check checks.Check, item map[string]any, cache map[string][]map[string]any) ([]Finding, error) {
	client, err := newPrometheusClient()
	if err != nil {
		return nil, nil
	}
	now := currentRuntime.Now
	if now.IsZero() {
		now = time.Now().UTC()
	}
	start := now.Add(-7 * 24 * time.Hour)
	coverage, err := client.QueryRange(`(1 - avg(rate(node_cpu_seconds_total{mode="idle"}[5m]))) * 100`, start.Format(time.RFC3339), now.Format(time.RFC3339), "6h", int(numberThreshold("prometheus_query_retries", 2)), int(numberThreshold("prometheus_retry_delay_seconds", 2)))
	coverageDays := maxCoverageDays(coverage)
	if err != nil || coverageDays < 6.9 {
		return []Finding{{Namespace: "(cluster)", Resource: "prometheus/node-sizing", Value: fmt.Sprintf("%.2f", coverageDays), Message: "Insufficient Prometheus history for node sizing recommendations"}}, nil
	}
	cpuSeries, err := client.Query(`quantile_over_time(0.95, ((1 - avg by(instance)(rate(node_cpu_seconds_total{mode="idle"}[5m]))) * 100)[7d:15m])`, int(numberThreshold("prometheus_query_retries", 2)), int(numberThreshold("prometheus_retry_delay_seconds", 2)))
	if err != nil {
		return nil, err
	}
	memSeries, err := client.Query(`quantile_over_time(0.95, ((1 - (node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes)) * 100)[7d:15m])`, int(numberThreshold("prometheus_query_retries", 2)), int(numberThreshold("prometheus_retry_delay_seconds", 2)))
	if err != nil {
		return nil, err
	}
	nodes, err := getCachedItems(cache, "nodes")
	if err != nil {
		return nil, err
	}
	downCPU := numberThreshold("node_sizing_downsize_cpu_p95", 35)
	downMem := numberThreshold("node_sizing_downsize_mem_p95", 40)
	upCPU := numberThreshold("node_sizing_upsize_cpu_p95", 80)
	upMem := numberThreshold("node_sizing_upsize_mem_p95", 85)
	var findings []Finding
	for _, node := range nodes {
		name := stringifyLookup(node, "metadata.name")
		aliases := nodeAliases(node)
		cpu := findPromMetricValue(cpuSeries, name, aliases)
		mem := findPromMetricValue(memSeries, name, aliases)
		if cpu == nil && mem == nil {
			continue
		}
		switch {
		case (cpu != nil && *cpu >= upCPU) || (mem != nil && *mem >= upMem):
			findings = append(findings, Finding{Namespace: "(cluster)", Resource: "node/" + name, Value: fmt.Sprintf("cpu_p95=%.2f mem_p95=%.2f", valueOrZero(cpu), valueOrZero(mem)), Message: "Saturated"})
		case cpu != nil && mem != nil && *cpu <= downCPU && *mem <= downMem:
			findings = append(findings, Finding{Namespace: "(cluster)", Resource: "node/" + name, Value: fmt.Sprintf("cpu_p95=%.2f mem_p95=%.2f", *cpu, *mem), Message: "Underutilized"})
		}
	}
	return findings, nil
}

func runPROM007(check checks.Check, item map[string]any, cache map[string][]map[string]any) ([]Finding, error) {
	client, err := newPrometheusClient()
	if err != nil {
		return nil, nil
	}
	now := currentRuntime.Now
	if now.IsZero() {
		now = time.Now().UTC()
	}
	start := now.Add(-7 * 24 * time.Hour)
	coverage, err := client.QueryRange(`sum(rate(container_cpu_usage_seconds_total{container!="",pod!=""}[5m])) * 1000`, start.Format(time.RFC3339), now.Format(time.RFC3339), "6h", int(numberThreshold("prometheus_query_retries", 2)), int(numberThreshold("prometheus_retry_delay_seconds", 2)))
	coverageDays := maxCoverageDays(coverage)
	if err != nil || coverageDays < 6.9 {
		return []Finding{{Namespace: "(cluster)", Resource: "prometheus/pod-sizing", Value: fmt.Sprintf("%.2f", coverageDays), Message: "Insufficient Prometheus history for pod sizing recommendations"}}, nil
	}
	cpuSeries, err := client.Query(`quantile_over_time(0.95, (sum by(namespace,pod,container) (rate(container_cpu_usage_seconds_total{container!="",container!="POD",pod!=""}[5m])) * 1000)[7d:15m])`, int(numberThreshold("prometheus_query_retries", 2)), int(numberThreshold("prometheus_retry_delay_seconds", 2)))
	if err != nil {
		return nil, err
	}
	memSeries, err := client.Query(`quantile_over_time(0.95, (max by(namespace,pod,container) (container_memory_working_set_bytes{container!="",container!="POD",pod!=""}) / 1024 / 1024)[7d:15m])`, int(numberThreshold("prometheus_query_retries", 2)), int(numberThreshold("prometheus_retry_delay_seconds", 2)))
	if err != nil {
		return nil, err
	}
	cpuMap := metricMapByKey(cpuSeries)
	memMap := metricMapByKey(memSeries)
	targetCPU := numberThreshold("pod_sizing_target_cpu_utilization", 65)
	targetMem := numberThreshold("pod_sizing_target_mem_utilization", 75)
	cpuFloor := numberThreshold("pod_sizing_cpu_request_floor_mcores", 25)
	memFloor := numberThreshold("pod_sizing_mem_request_floor_mib", 128)
	memBuffer := numberThreshold("pod_sizing_mem_limit_buffer_percent", 20)
	pods, err := getCachedItems(cache, "pods")
	if err != nil {
		return nil, err
	}
	var findings []Finding
	for _, pod := range pods {
		ns := namespaceOf(pod)
		podName := stringifyLookup(pod, "metadata.name")
		for _, c := range containersOnly(pod) {
			name := stringifyLookup(c, "name")
			key := ns + "|" + podName + "|" + name
			cpuP95, hasCPU := cpuMap[key]
			memP95, hasMem := memMap[key]
			if !hasCPU && !hasMem {
				continue
			}
			cpuReq := cpuMillicores(stringifyLookup(c, "resources.requests.cpu"))
			memReq := memoryMi(stringifyLookup(c, "resources.requests.memory"))
			memLim := memoryMi(stringifyLookup(c, "resources.limits.memory"))
			recCPU := maxFloat(cpuFloor, ceilStep(cpuP95/targetCPU*100, 10))
			recMem := maxFloat(memFloor, ceilStep(memP95/targetMem*100, 16))
			recMemLimit := ceilStep(recMem*(1+(memBuffer/100)), 1)
			cpuNeeds := !approxWithin(cpuReq, recCPU, 0.8, 1.25)
			memNeeds := !approxWithin(memReq, recMem, 0.8, 1.25)
			memLimitNeeds := memLim == 0 || memLim < recMemLimit*0.9
			if !cpuNeeds && !memNeeds && !memLimitNeeds {
				continue
			}
			findings = append(findings, Finding{
				Namespace: ns,
				Resource:  "pod/" + podName,
				Value:     name,
				Message:   fmt.Sprintf("cpu_req=%0.fm cpu_rec=%0.fm mem_req=%0.fMi mem_rec=%0.fMi mem_limit=%0.fMi mem_limit_rec=%0.fMi", cpuReq, recCPU, memReq, recMem, memLim, recMemLimit),
			})
		}
	}
	return findings, nil
}

func runWRK013(check checks.Check, item map[string]any, cache map[string][]map[string]any) ([]Finding, error) {
	ns := namespaceOf(item)
	podName := stringifyLookup(item, "metadata.name")
	specContainers := containersOnly(item)
	specByName := map[string]map[string]any{}
	for _, c := range specContainers {
		specByName[stringifyLookup(c, "name")] = c
	}
	var findings []Finding
	for _, cs := range asSlice(mustResolve(item, "status.containerStatuses")) {
		name := stringifyLookup(cs, "name")
		restartCount := asInt64(mustResolve(cs, "restartCount"))
		var reasons []string
		if stringifyLookup(cs, "state.waiting.reason") == "CrashLoopBackOff" {
			reasons = append(reasons, "CrashLoopBackOff")
		}
		if stringifyLookup(cs, "lastState.terminated.reason") == "OOMKilled" || stringifyLookup(cs, "state.terminated.reason") == "OOMKilled" {
			reasons = append(reasons, "OOMKilled")
		}
		if restartCount >= 5 {
			reasons = append(reasons, fmt.Sprintf("HighRestarts(%d)", restartCount))
		}
		if len(reasons) == 0 {
			continue
		}
		spec := specByName[name]
		findings = append(findings, Finding{
			Namespace: ns,
			Resource:  "pod/" + podName,
			Value:     name,
			Message:   strings.Join(reasons, ", ") + fmt.Sprintf(" cpuReq=%s cpuLimit=%s memReq=%s memLimit=%s", stringifyLookup(spec, "resources.requests.cpu"), stringifyLookup(spec, "resources.limits.cpu"), stringifyLookup(spec, "resources.requests.memory"), stringifyLookup(spec, "resources.limits.memory")),
		})
	}
	return findings, nil
}

func runWRK015(check checks.Check, item map[string]any, cache map[string][]map[string]any) ([]Finding, error) {
	if stringifyLookup(item, "metadata.name") == "" {
		return runSyntheticWorkloadCheck(cache, func(workload map[string]any) []Finding {
			return spreadConstraintFindings(workload)
		})
	}
	return spreadConstraintFindings(item), nil
}

func runWRK010(check checks.Check, item map[string]any, cache map[string][]map[string]any) ([]Finding, error) {
	ns := namespaceOf(item)
	hpaName := stringifyLookup(item, "metadata.name")
	targetKind := stringifyLookup(item, "spec.scaleTargetRef.kind")
	targetName := stringifyLookup(item, "spec.scaleTargetRef.name")
	workload, err := resolveTargetWorkload(cache, ns, targetKind, targetName)
	if err != nil || workload == nil {
		return nil, err
	}
	resourceMetrics := []string{}
	for _, metric := range asSlice(mustResolve(item, "spec.metrics")) {
		if stringifyLookup(metric, "type") == "Resource" {
			name := stringifyLookup(metric, "resource.name")
			if name == "cpu" || name == "memory" {
				resourceMetrics = append(resourceMetrics, name)
			}
		}
	}
	if len(resourceMetrics) == 0 {
		return nil, nil
	}
	var findings []Finding
	for _, metricName := range resourceMetrics {
		var missing []string
		for _, c := range containersFromTemplate(workload) {
			req := stringifyLookup(c, "resources.requests."+metricName)
			if req == "" {
				missing = append(missing, stringifyLookup(c, "name"))
			}
		}
		if len(missing) == 0 {
			continue
		}
		findings = append(findings, Finding{
			Namespace: ns,
			Resource:  "hpa/" + hpaName,
			Value:     targetKind + "/" + targetName,
			Message:   fmt.Sprintf("Containers missing %s requests: %s", metricName, strings.Join(missing, ", ")),
		})
	}
	return findings, nil
}

func runWRK011(check checks.Check, item map[string]any, cache map[string][]map[string]any) ([]Finding, error) {
	ns := namespaceOf(item)
	vpaName := stringifyLookup(item, "metadata.name")
	targetKind := stringifyLookup(item, "spec.targetRef.kind")
	targetName := stringifyLookup(item, "spec.targetRef.name")
	if targetKind == "" || targetName == "" {
		return nil, nil
	}
	updateMode := stringifyLookup(item, "spec.updatePolicy.updateMode")
	if updateMode == "" {
		updateMode = "Auto"
	}
	if updateMode != "Auto" && updateMode != "Recreate" {
		return nil, nil
	}
	workload, err := resolveTargetWorkload(cache, ns, targetKind, targetName)
	if err != nil || workload == nil {
		return nil, err
	}
	withRequests := false
	for _, c := range containersFromTemplate(workload) {
		if stringifyLookup(c, "resources.requests.cpu") != "" || stringifyLookup(c, "resources.requests.memory") != "" {
			withRequests = true
			break
		}
	}
	if !withRequests {
		return nil, nil
	}
	managedBy := stringifyLookup(workload, "metadata.labels.app.kubernetes.io/managed-by")
	if managedBy == "" {
		managedBy = "unknown"
	}
	isDeclarative := map[string]bool{"helm": true, "argocd": true, "flux": true, "kustomize": true, "terraform": true}[strings.ToLower(managedBy)]
	hpas, err := getCachedItems(cache, "horizontalpodautoscalers")
	if err != nil {
		return nil, err
	}
	hasHPAConflict := false
	for _, hpa := range hpas {
		if namespaceOf(hpa) != ns || stringifyLookup(hpa, "spec.scaleTargetRef.kind") != targetKind || stringifyLookup(hpa, "spec.scaleTargetRef.name") != targetName {
			continue
		}
		for _, metric := range asSlice(mustResolve(hpa, "spec.metrics")) {
			if stringifyLookup(metric, "type") == "Resource" {
				name := stringifyLookup(metric, "resource.name")
				if name == "cpu" || name == "memory" {
					hasHPAConflict = true
					break
				}
			}
		}
		if hasHPAConflict {
			break
		}
	}
	if !isDeclarative && !hasHPAConflict {
		return nil, nil
	}
	reasons := []string{}
	if isDeclarative {
		reasons = append(reasons, "Declarative manager detected ("+managedBy+")")
	}
	if hasHPAConflict {
		reasons = append(reasons, "HPA also scales this target via CPU/memory metrics")
	}
	return []Finding{{Namespace: ns, Resource: "verticalpodautoscaler/" + vpaName, Value: targetKind + "/" + targetName, Message: strings.Join(reasons, "; ")}}, nil
}

func runWRK012(check checks.Check, item map[string]any, cache map[string][]map[string]any) ([]Finding, error) {
	if stringifyLookup(item, "metadata.name") != "" {
		return nil, nil
	}
	workloads, err := allTemplateWorkloads(cache)
	if err != nil {
		return nil, err
	}
	pdbs, err := getCachedItems(cache, "poddisruptionbudgets")
	if err != nil {
		return nil, err
	}
	var findings []Finding
	for _, w := range workloads {
		replicas := asInt64(mustResolve(w, "spec.replicas"))
		if replicas == 0 {
			replicas = 1
		}
		if replicas < 2 {
			continue
		}
		ns := namespaceOf(w)
		labels := mustResolve(w, "spec.template.metadata.labels")
		matching := []map[string]any{}
		for _, p := range pdbs {
			if namespaceOf(p) == ns && selectorMatchesLabels(mustResolve(p, "spec.selector.matchLabels"), labels) {
				matching = append(matching, p)
			}
		}
		workloadRef := stringifyLookup(w, "kind") + "/" + stringifyLookup(w, "metadata.name")
		if len(matching) == 0 {
			findings = append(findings, Finding{Namespace: ns, Resource: strings.ToLower(stringifyLookup(w, "kind")) + "/" + stringifyLookup(w, "metadata.name"), Value: fmt.Sprintf("%d", replicas), Message: "No matching PDB for replicated workload"})
			continue
		}
		for _, p := range matching {
			minRaw := fmt.Sprint(mustResolve(p, "spec.minAvailable"))
			maxRaw := fmt.Sprint(mustResolve(p, "spec.maxUnavailable"))
			minVal := resolveIntOrPercent(mustResolve(p, "spec.minAvailable"), replicas)
			maxVal := resolveIntOrPercent(mustResolve(p, "spec.maxUnavailable"), replicas)
			var issues []string
			if minVal != nil && *minVal >= replicas {
				issues = append(issues, "minAvailable may be too strict for disruptions")
			}
			if maxVal != nil && *maxVal <= 0 {
				issues = append(issues, "maxUnavailable blocks voluntary disruption")
			}
			if maxVal != nil && *maxVal >= replicas {
				issues = append(issues, "maxUnavailable may be too permissive")
			}
			if len(issues) == 0 {
				continue
			}
			setting := "unset"
			if minRaw != "<nil>" {
				setting = "minAvailable=" + minRaw
			} else if maxRaw != "<nil>" {
				setting = "maxUnavailable=" + maxRaw
			}
			findings = append(findings, Finding{Namespace: ns, Resource: workloadRef, Value: stringifyLookup(p, "metadata.name") + " " + setting, Message: strings.Join(issues, "; ")})
		}
	}
	return findings, nil
}

func runCFG001(check checks.Check, item map[string]any, cache map[string][]map[string]any) ([]Finding, error) {
	name := strings.TrimSpace(stringifyLookup(item, "metadata.name"))
	if strings.HasPrefix(name, "sh.helm.release.v1.") || name == "kube-root-ca.crt" {
		return nil, nil
	}

	used, err := usedConfigMaps(cache)
	if err != nil {
		return nil, err
	}
	if used[name] {
		return nil, nil
	}

	return []Finding{{
		Namespace: namespaceOf(item),
		Resource:  "configmap/" + name,
		Value:     "-",
		Message:   "ConfigMap is not used by any workloads or services.",
	}}, nil
}

func runCFG002(check checks.Check, item map[string]any, cache map[string][]map[string]any) ([]Finding, error) {
	name := strings.TrimSpace(stringifyLookup(item, "metadata.name"))
	if name == "kube-root-ca" || name == "istio-ca-root" {
		return nil, nil
	}
	all, err := getCachedItems(cache, "configmaps")
	if err != nil {
		return nil, err
	}
	var namespaces []string
	for _, cm := range all {
		if stringifyLookup(cm, "metadata.name") == name && name != "kube-root-ca" && name != "istio-ca-root" {
			namespaces = append(namespaces, namespaceOf(cm))
		}
	}
	if len(namespaces) <= 1 {
		return nil, nil
	}
	sort.Strings(namespaces)
	return []Finding{{
		Namespace: "-",
		Resource:  "configmap/" + name,
		Value:     "-",
		Message:   "Found in namespaces: " + strings.Join(namespaces, ", "),
	}}, nil
}

func runCFG003(check checks.Check, item map[string]any, cache map[string][]map[string]any) ([]Finding, error) {
	data, _ := mustResolve(item, "data").(map[string]any)
	size := 0
	for _, v := range data {
		size += len(fmt.Sprint(v))
	}
	if size <= 1048576 {
		return nil, nil
	}
	return []Finding{{
		Namespace: namespaceOf(item),
		Resource:  "configmap/" + stringifyLookup(item, "metadata.name"),
		Value:     fmt.Sprintf("%d bytes", size),
		Message:   "ConfigMap exceeds 1 MiB",
	}}, nil
}

func runNS001(check checks.Check, item map[string]any, cache map[string][]map[string]any) ([]Finding, error) {
	ns := stringifyLookup(item, "metadata.name")
	pods, err := getCachedItems(cache, "pods")
	if err != nil {
		return nil, err
	}
	hasPods := false
	for _, pod := range pods {
		if namespaceOf(pod) == ns {
			hasPods = true
			break
		}
	}
	if hasPods {
		return nil, nil
	}

	resourceKinds := []string{"secrets", "persistentvolumeclaims", "services", "configmaps", "deployments", "statefulsets", "daemonsets"}
	hasOther := false
	for _, kind := range resourceKinds {
		items, err := getCachedItems(cache, kind)
		if err != nil {
			return nil, err
		}
		for _, candidate := range items {
			if namespaceOf(candidate) == ns {
				hasOther = true
				break
			}
		}
		if hasOther {
			break
		}
	}

	status := "📂 Empty"
	issue := "No pods and no major resources"
	if hasOther {
		status = "⚠️ Partial"
		issue = "No pods, but other resources exist"
	}
	return []Finding{{
		Namespace: ns,
		Resource:  "namespace/" + ns,
		Value:     status,
		Message:   issue,
	}}, nil
}

func runNS002(check checks.Check, item map[string]any, cache map[string][]map[string]any) ([]Finding, error) {
	ns := stringifyLookup(item, "metadata.name")
	quotas, err := getCachedItems(cache, "resourcequotas")
	if err != nil {
		return nil, err
	}
	var matches []map[string]any
	for _, q := range quotas {
		if namespaceOf(q) == ns {
			matches = append(matches, q)
		}
	}
	if len(matches) == 0 {
		return []Finding{{Namespace: ns, Resource: "namespace/" + ns, Value: "", Message: "❌ No ResourceQuota"}}, nil
	}
	hasCPU, hasMemory, hasPods := false, false, false
	for _, q := range matches {
		hard, _ := mustResolve(q, "status.hard").(map[string]any)
		for key := range hard {
			switch key {
			case "requests.cpu", "limits.cpu":
				hasCPU = true
			case "requests.memory", "limits.memory":
				hasMemory = true
			case "pods":
				hasPods = true
			}
		}
	}
	if hasCPU && hasMemory && hasPods {
		return nil, nil
	}
	var missing []string
	if !hasCPU {
		missing = append(missing, "CPU")
	}
	if !hasMemory {
		missing = append(missing, "Memory")
	}
	if !hasPods {
		missing = append(missing, "Pods")
	}
	return []Finding{{Namespace: ns, Resource: "namespace/" + ns, Value: "", Message: "⚠️ Missing: " + strings.Join(missing, ", ")}}, nil
}

func runNS003(check checks.Check, item map[string]any, cache map[string][]map[string]any) ([]Finding, error) {
	ns := stringifyLookup(item, "metadata.name")
	limitRanges, err := getCachedItems(cache, "limitranges")
	if err != nil {
		return nil, err
	}
	for _, lr := range limitRanges {
		if namespaceOf(lr) == ns {
			return nil, nil
		}
	}
	return []Finding{{Namespace: ns, Resource: "namespace/" + ns, Value: "", Message: "❌ No LimitRange"}}, nil
}

func runNS004(check checks.Check, item map[string]any, cache map[string][]map[string]any) ([]Finding, error) {
	if namespaceOf(item) != "default" {
		return nil, nil
	}
	return []Finding{{Namespace: "default", Resource: "pod/" + stringifyLookup(item, "metadata.name"), Value: "", Message: "Pod is running in the default namespace"}}, nil
}

func runPOD001(check checks.Check, item map[string]any, cache map[string][]map[string]any) ([]Finding, error) {
	restarts := int64(0)
	for _, st := range asSlice(mustResolve(item, "status.containerStatuses")) {
		restarts += asInt64(mustResolve(st, "restartCount"))
	}
	status := ""
	switch {
	case restarts > 10:
		status = "Critical"
	case restarts > 3:
		status = "Warning"
	default:
		return nil, nil
	}
	return []Finding{{Namespace: namespaceOf(item), Resource: "pod/" + stringifyLookup(item, "metadata.name"), Value: fmt.Sprintf("%d", restarts), Message: status}}, nil
}

func runPOD002(check checks.Check, item map[string]any, cache map[string][]map[string]any) ([]Finding, error) {
	if stringifyLookup(item, "status.phase") != "Running" {
		return nil, nil
	}
	start := parseTime(stringifyLookup(item, "status.startTime"))
	if start.IsZero() {
		return nil, nil
	}
	ageDays := int(time.Since(start).Hours() / 24)
	status := ""
	switch {
	case ageDays > 30:
		status = "Critical"
	case ageDays > 15:
		status = "Warning"
	default:
		return nil, nil
	}
	return []Finding{{Namespace: namespaceOf(item), Resource: "pod/" + stringifyLookup(item, "metadata.name"), Value: fmt.Sprintf("%d", ageDays), Message: status}}, nil
}

func runPOD006(check checks.Check, item map[string]any, cache map[string][]map[string]any) ([]Finding, error) {
	name := stringifyLookup(item, "metadata.name")
	if !strings.Contains(name, "debugger") {
		return nil, nil
	}
	return []Finding{{Namespace: namespaceOf(item), Resource: "pod/" + name, Value: stringifyLookup(item, "spec.nodeName"), Message: stringifyLookup(item, "status.phase")}}, nil
}

func runPOD007(check checks.Check, item map[string]any, cache map[string][]map[string]any) ([]Finding, error) {
	podName := stringifyLookup(item, "metadata.name")
	var findings []Finding
	for _, c := range appendContainerSets(item) {
		image := strings.TrimSpace(stringifyLookup(c, "image"))
		if image == "" {
			continue
		}
		if strings.Contains(image, "@sha256:") {
			continue
		}
		lastSlash := strings.LastIndex(image, "/")
		tagIdx := strings.LastIndex(image, ":")
		missingTag := tagIdx <= lastSlash
		latest := strings.HasSuffix(image, ":latest")
		if !missingTag && !latest {
			continue
		}
		reason := "Image omits explicit tag"
		if latest {
			reason = "Image uses latest tag"
		}
		findings = append(findings, Finding{
			Namespace: namespaceOf(item),
			Resource:  "pod/" + podName,
			Value:     image,
			Message:   fmt.Sprintf("Container %s: %s", stringifyLookup(c, "name"), reason),
		})
	}
	return findings, nil
}

func runPOD008(check checks.Check, item map[string]any, cache map[string][]map[string]any) ([]Finding, error) {
	value := mustResolve(item, "spec.automountServiceAccountToken")
	if flag, ok := value.(bool); ok && !flag {
		return nil, nil
	}
	return []Finding{{
		Namespace: namespaceOf(item),
		Resource:  "pod/" + stringifyLookup(item, "metadata.name"),
		Value:     fmt.Sprint(value),
		Message:   "Pod automounts API credentials",
	}}, nil
}

func runJOB001(check checks.Check, item map[string]any, cache map[string][]map[string]any) ([]Finding, error) {
	start := parseTime(stringifyLookup(item, "status.startTime"))
	if start.IsZero() || time.Since(start) <= 2*time.Hour || jobComplete(item) {
		return nil, nil
	}
	return []Finding{{Namespace: namespaceOf(item), Resource: "job/" + stringifyLookup(item, "metadata.name"), Value: fmt.Sprintf("%d", int(time.Since(start).Hours())), Message: "🟡 Stuck"}}, nil
}

func runJOB002(check checks.Check, item map[string]any, cache map[string][]map[string]any) ([]Finding, error) {
	failed := asInt64(mustResolve(item, "status.failed"))
	succeeded := asInt64(mustResolve(item, "status.succeeded"))
	start := parseTime(stringifyLookup(item, "status.startTime"))
	if failed == 0 || succeeded > 0 || start.IsZero() || time.Since(start) <= 2*time.Hour {
		return nil, nil
	}
	return []Finding{{Namespace: namespaceOf(item), Resource: "job/" + stringifyLookup(item, "metadata.name"), Value: fmt.Sprintf("%d", failed), Message: "🔴 Failed"}}, nil
}

func runWRK001(check checks.Check, item map[string]any, cache map[string][]map[string]any) ([]Finding, error) {
	desired := asInt64(mustResolve(item, "status.desiredNumberScheduled"))
	ready := asInt64(mustResolve(item, "status.numberReady"))
	if desired == ready {
		return nil, nil
	}
	return []Finding{{Namespace: namespaceOf(item), Resource: "daemonset/" + stringifyLookup(item, "metadata.name"), Value: fmt.Sprintf("%d/%d", ready, desired), Message: "DaemonSet is not running on all desired nodes."}}, nil
}

func runWRK002(check checks.Check, item map[string]any, cache map[string][]map[string]any) ([]Finding, error) {
	desired := asInt64(mustResolve(item, "spec.replicas"))
	if desired == 0 {
		desired = 1
	}
	available := asInt64(mustResolve(item, "status.availableReplicas"))
	if available >= desired {
		return nil, nil
	}
	return []Finding{{Namespace: namespaceOf(item), Resource: "deployment/" + stringifyLookup(item, "metadata.name"), Value: fmt.Sprintf("%d/%d", available, desired), Message: "Deployment has fewer available replicas than desired."}}, nil
}

func runWRK003(check checks.Check, item map[string]any, cache map[string][]map[string]any) ([]Finding, error) {
	desired := asInt64(mustResolve(item, "spec.replicas"))
	if desired == 0 {
		desired = 1
	}
	ready := asInt64(mustResolve(item, "status.readyReplicas"))
	if ready >= desired {
		return nil, nil
	}
	return []Finding{{Namespace: namespaceOf(item), Resource: "statefulset/" + stringifyLookup(item, "metadata.name"), Value: fmt.Sprintf("%d/%d", ready, desired), Message: "StatefulSet has fewer ready replicas than desired."}}, nil
}

func runWRK004(check checks.Check, item map[string]any, cache map[string][]map[string]any) ([]Finding, error) {
	ns := namespaceOf(item)
	targetKind := stringifyLookup(item, "spec.scaleTargetRef.kind")
	targetName := stringifyLookup(item, "spec.scaleTargetRef.name")
	targetRef := targetKind + "/" + targetName

	var findings []Finding
	if !hpaTargetExists(cache, ns, targetKind, targetName) {
		findings = append(findings, Finding{Namespace: ns, Resource: "hpa/" + stringifyLookup(item, "metadata.name"), Value: targetRef, Message: "❌ Target not found"})
		return findings, nil
	}
	if len(asSlice(mustResolve(item, "status.currentMetrics"))) == 0 {
		findings = append(findings, Finding{Namespace: ns, Resource: "hpa/" + stringifyLookup(item, "metadata.name"), Value: targetRef, Message: "❌ No metrics available"})
	}
	for _, c := range asSlice(mustResolve(item, "status.conditions")) {
		typ := stringifyLookup(c, "type")
		if stringifyLookup(c, "status") != "False" {
			continue
		}
		switch typ {
		case "AbleToScale":
			findings = append(findings, Finding{Namespace: ns, Resource: "hpa/" + stringifyLookup(item, "metadata.name"), Value: targetRef, Message: "⚠️ Scaling disabled: " + stringifyLookup(c, "reason")})
		case "ScalingActive":
			findings = append(findings, Finding{Namespace: ns, Resource: "hpa/" + stringifyLookup(item, "metadata.name"), Value: targetRef, Message: "⚠️ Scaling inactive: " + stringifyLookup(c, "reason")})
		}
	}
	current := asInt64(mustResolve(item, "status.currentReplicas"))
	desired := asInt64(mustResolve(item, "status.desiredReplicas"))
	if current != 0 && desired != 0 && current != desired {
		findings = append(findings, Finding{Namespace: ns, Resource: "hpa/" + stringifyLookup(item, "metadata.name"), Value: fmt.Sprintf("%d → %d", current, desired), Message: "⚠️ Scaling mismatch"})
	}
	return findings, nil
}

func runWRK005(check checks.Check, item map[string]any, cache map[string][]map[string]any) ([]Finding, error) {
	if stringifyLookup(item, "metadata.name") == "" {
		return runSyntheticWorkloadCheck(cache, func(workload map[string]any) []Finding {
			return runWorkloadResourceRequirement(workload, "request", false)
		})
	}
	return runWorkloadResourceRequirement(item, "request", false), nil
}

func runWRK014(check checks.Check, item map[string]any, cache map[string][]map[string]any) ([]Finding, error) {
	if stringifyLookup(item, "metadata.name") == "" {
		return runSyntheticWorkloadCheck(cache, func(workload map[string]any) []Finding {
			return runWorkloadResourceRequirement(workload, "limit", true)
		})
	}
	return runWorkloadResourceRequirement(item, "limit", true), nil
}

func runWRK006(check checks.Check, item map[string]any, cache map[string][]map[string]any) ([]Finding, error) {
	if stringifyLookup(item, "metadata.name") == "" {
		pdbs, err := getCachedItems(cache, "poddisruptionbudgets")
		if err != nil {
			return nil, err
		}
		var findings []Finding
		for _, pdb := range pdbs {
			rows, err := runWRK006(check, pdb, cache)
			if err != nil {
				return nil, err
			}
			findings = append(findings, rows...)
		}
		return dedupeFindings(findings), nil
	}
	ns := namespaceOf(item)
	name := stringifyLookup(item, "metadata.name")
	var findings []Finding
	if asInt64(mustResolve(item, "status.expectedPods")) == 0 {
		findings = append(findings, Finding{Namespace: ns, Resource: "poddisruptionbudget/" + name, Value: name, Message: "⚠️ Matches 0 pods"})
	}
	if weak := weakPDB(item); weak != "" {
		findings = append(findings, Finding{Namespace: ns, Resource: "poddisruptionbudget/" + name, Value: name, Message: weak})
	}
	deployments, err := getCachedItems(cache, "deployments")
	if err != nil {
		return nil, err
	}
	statefulsets, err := getCachedItems(cache, "statefulsets")
	if err != nil {
		return nil, err
	}
	pdbs, err := getCachedItems(cache, "poddisruptionbudgets")
	if err != nil {
		return nil, err
	}
	for _, workload := range append(deployments, statefulsets...) {
		if namespaceOf(workload) != ns {
			continue
		}
		labels, _ := mustResolve(workload, "spec.template.metadata.labels").(map[string]any)
		if len(labels) == 0 {
			continue
		}
		matched := false
		for _, pdb := range pdbs {
			if namespaceOf(pdb) == ns && selectorMatchesLabels(mustResolve(pdb, "spec.selector.matchLabels"), labels) {
				matched = true
				break
			}
		}
		if !matched {
			findings = append(findings, Finding{Namespace: ns, Resource: strings.ToLower(stringifyLookup(workload, "kind")) + "/" + stringifyLookup(workload, "metadata.name"), Value: "", Message: "❌ No matching PDB"})
		}
	}
	return findings, nil
}

func runWRK007(check checks.Check, item map[string]any, cache map[string][]map[string]any) ([]Finding, error) {
	if stringifyLookup(item, "metadata.name") == "" {
		return runSyntheticWorkloadCheck(cache, runProbeCheck)
	}
	return runProbeCheck(item), nil
}

func runWRK008(check checks.Check, item map[string]any, cache map[string][]map[string]any) ([]Finding, error) {
	selector := mustResolve(item, "spec.selector.matchLabels")
	if selector == nil {
		return nil, nil
	}
	pods, err := getCachedItems(cache, "pods")
	if err != nil {
		return nil, err
	}
	ns := namespaceOf(item)
	for _, pod := range pods {
		if namespaceOf(pod) == ns && selectorMatchesLabels(selector, mustResolve(pod, "metadata.labels")) {
			return nil, nil
		}
	}
	return []Finding{{Namespace: ns, Resource: "deployment/" + stringifyLookup(item, "metadata.name"), Value: "0 matching pods", Message: "Deployment selector does not match any pods"}}, nil
}

func runWRK009(check checks.Check, item map[string]any, cache map[string][]map[string]any) ([]Finding, error) {
	ns := namespaceOf(item)
	name := stringifyLookup(item, "metadata.name")
	selector := mustResolve(item, "spec.selector.matchLabels")
	templateLabels := mustResolve(item, "spec.template.metadata.labels")
	var findings []Finding
	if !selectorMatchesLabels(selector, templateLabels) {
		findings = append(findings, Finding{Namespace: ns, Resource: "deployment/" + name, Value: "", Message: "Deployment selector does not match pod template labels"})
	}
	services, err := getCachedItems(cache, "services")
	if err != nil {
		return nil, err
	}
	for _, svc := range services {
		if namespaceOf(svc) != ns {
			continue
		}
		sel := mustResolve(svc, "spec.selector")
		if sel == nil || selectorMatchesLabels(sel, templateLabels) {
			continue
		}
		if selectorOverlaps(sel, templateLabels) {
			findings = append(findings, Finding{Namespace: ns, Resource: "deployment/" + name, Value: "service/" + stringifyLookup(svc, "metadata.name"), Message: "Service selector does not align with deployment pod labels"})
		}
	}
	return findings, nil
}

func runRBAC001(check checks.Check, item map[string]any, cache map[string][]map[string]any) ([]Finding, error) {
	return rbacMisconfigFindings(cache)
}

func runRBAC002(check checks.Check, item map[string]any, cache map[string][]map[string]any) ([]Finding, error) {
	return rbacOverexposureFindings(cache)
}

func runRBAC003(check checks.Check, item map[string]any, cache map[string][]map[string]any) ([]Finding, error) {
	name := stringifyLookup(item, "metadata.name")
	ns := namespaceOf(item)
	used, err := usedServiceAccounts(cache)
	if err != nil {
		return nil, err
	}
	if used[ns+"/"+name] {
		return nil, nil
	}
	return []Finding{{Namespace: ns, Resource: "serviceaccount/" + name, Value: name, Message: "ServiceAccount not used by pods or RBAC bindings"}}, nil
}

func runRBAC004(check checks.Check, item map[string]any, cache map[string][]map[string]any) ([]Finding, error) {
	return orphanedRoles(cache)
}

func getCachedItems(cache map[string][]map[string]any, kind string) ([]map[string]any, error) {
	return getItems(currentRuntime.KubeContext, currentRuntime.KubeClient, cache, kind)
}

func usedConfigMaps(cache map[string][]map[string]any) (map[string]bool, error) {
	used := map[string]bool{}
	for _, kind := range []string{"pods", "deployments", "statefulsets", "daemonsets", "cronjobs", "jobs", "replicasets"} {
		items, err := getCachedItems(cache, kind)
		if err != nil {
			continue
		}
		for _, item := range items {
			addMountedRefNames(used, item, "configMap", "configMap.name")
			addContainerRefs(used, item, "configMapKeyRef.name", "configMapRef.name")
		}
	}
	return used, nil
}

func usedSecrets(cache map[string][]map[string]any) (map[string]bool, error) {
	used := map[string]bool{}
	for _, kind := range []string{"pods", "deployments", "statefulsets", "daemonsets"} {
		items, err := getCachedItems(cache, kind)
		if err != nil {
			return nil, err
		}
		for _, item := range items {
			ns := namespaceOf(item)
			for _, volume := range asSlice(mustResolve(item, "spec.volumes")) {
				if name := stringifyLookup(volume, "secret.secretName"); name != "" {
					used[ns+"/"+name] = true
					used["*/"+name] = true
				}
			}
			for _, container := range allContainers(item) {
				for _, env := range asSlice(mustResolve(container, "env")) {
					if name := stringifyLookup(env, "valueFrom.secretKeyRef.name"); name != "" {
						used[ns+"/"+name] = true
						used["*/"+name] = true
					}
				}
				for _, envFrom := range asSlice(mustResolve(container, "envFrom")) {
					if name := stringifyLookup(envFrom, "secretRef.name"); name != "" {
						used[ns+"/"+name] = true
						used["*/"+name] = true
					}
				}
			}
		}
	}
	for _, kind := range []string{"ingresses", "serviceaccounts"} {
		items, err := getCachedItems(cache, kind)
		if err != nil {
			continue
		}
		for _, item := range items {
			ns := namespaceOf(item)
			if kind == "ingresses" {
				for _, tls := range asSlice(mustResolve(item, "spec.tls")) {
					if name := stringifyLookup(tls, "secretName"); name != "" {
						used[ns+"/"+name] = true
						used["*/"+name] = true
					}
				}
				continue
			}
			for _, secret := range asSlice(mustResolve(item, "secrets")) {
				if name := stringifyLookup(secret, "name"); name != "" {
					used[ns+"/"+name] = true
					used["*/"+name] = true
				}
			}
		}
	}
	return used, nil
}

func usedServiceAccounts(cache map[string][]map[string]any) (map[string]bool, error) {
	used := map[string]bool{}
	pods, err := getCachedItems(cache, "pods")
	if err != nil {
		return nil, err
	}
	for _, pod := range pods {
		if sa := stringifyLookup(pod, "spec.serviceAccountName"); sa != "" {
			used[namespaceOf(pod)+"/"+sa] = true
		}
	}
	for _, kind := range []string{"rolebindings", "clusterrolebindings"} {
		items, err := getCachedItems(cache, kind)
		if err != nil {
			return nil, err
		}
		for _, binding := range items {
			for _, s := range asSlice(mustResolve(binding, "subjects")) {
				if stringifyLookup(s, "kind") != "ServiceAccount" {
					continue
				}
				ns := stringifyLookup(s, "namespace")
				if ns == "" {
					ns = namespaceOf(binding)
				}
				name := stringifyLookup(s, "name")
				if ns != "" && name != "" {
					used[ns+"/"+name] = true
				}
			}
		}
	}
	return used, nil
}

func weakPDB(item map[string]any) string {
	if asInt64(mustResolve(item, "spec.minAvailable")) == 0 && stringifyLookup(item, "spec.minAvailable") != "" {
		return "⚠️ minAvailable = 0"
	}
	maxUnavailable := stringifyLookup(item, "spec.maxUnavailable")
	if maxUnavailable == "1" || maxUnavailable == "100%" {
		return "⚠️ maxUnavailable = 100%"
	}
	return ""
}

func runProbeCheck(item map[string]any) []Finding {
	ns := namespaceOf(item)
	name := stringifyLookup(item, "metadata.name")
	kind := strings.TrimSpace(stringifyLookup(item, "kind"))
	if kind == "" {
		kind = "Deployment"
	}
	var findings []Finding
	for _, c := range containersFromTemplate(item) {
		var missing []string
		if mustResolve(c, "readinessProbe") == nil {
			missing = append(missing, "readiness")
		}
		if mustResolve(c, "livenessProbe") == nil {
			missing = append(missing, "liveness")
		}
		if len(missing) == 0 {
			continue
		}
		findings = append(findings, Finding{
			Namespace: ns,
			Resource:  strings.ToLower(kind) + "/" + name,
			Value:     stringifyLookup(c, "name"),
			Message:   strings.Join(missing, ", ") + " missing",
		})
	}
	return findings
}

func runWorkloadResourceRequirement(item map[string]any, mode string, memoryOnly bool) []Finding {
	ns := namespaceOf(item)
	name := stringifyLookup(item, "metadata.name")
	kind := strings.TrimSpace(stringifyLookup(item, "kind"))
	if kind == "" {
		kind = "Pod"
	}
	var findings []Finding
	for _, c := range append(containersFromTemplate(item), initContainersFromTemplate(item)...) {
		containerType := "Container"
		if isInitContainer(item, c) {
			containerType = "InitContainer"
		}
		missing := []string{}
		if mode == "request" {
			if stringifyLookup(c, "resources.requests.cpu") == "" {
				missing = append(missing, "CPU request")
			}
			if stringifyLookup(c, "resources.requests.memory") == "" {
				missing = append(missing, "Memory request")
			}
		} else if memoryOnly {
			if stringifyLookup(c, "resources.limits.memory") == "" {
				missing = append(missing, "Memory limit")
			}
		}
		if len(missing) == 0 {
			continue
		}
		findings = append(findings, Finding{
			Namespace: ns,
			Resource:  strings.ToLower(kind) + "/" + name,
			Value:     stringifyLookup(c, "name"),
			Message:   containerType + ": " + strings.Join(missing, ", ") + " missing",
		})
	}
	return findings
}

func runSyntheticWorkloadCheck(cache map[string][]map[string]any, fn func(map[string]any) []Finding) ([]Finding, error) {
	workloads, err := allTemplateWorkloads(cache)
	if err != nil {
		return nil, err
	}
	var findings []Finding
	for _, workload := range workloads {
		findings = append(findings, fn(workload)...)
	}
	return dedupeFindings(findings), nil
}

func spreadConstraintFindings(workload map[string]any) []Finding {
	replicas := asInt64(mustResolve(workload, "spec.replicas"))
	if replicas == 0 {
		replicas = 1
	}
	if replicas <= 1 {
		return nil
	}
	podSpec := mustResolve(workload, "spec.template.spec")
	if podSpec == nil {
		return nil
	}
	required := asSlice(mustResolve(workload, "spec.template.spec.affinity.podAntiAffinity.requiredDuringSchedulingIgnoredDuringExecution"))
	preferred := asSlice(mustResolve(workload, "spec.template.spec.affinity.podAntiAffinity.preferredDuringSchedulingIgnoredDuringExecution"))
	spread := asSlice(mustResolve(workload, "spec.template.spec.topologySpreadConstraints"))
	if len(required) > 0 || len(preferred) > 0 || len(spread) > 0 {
		return nil
	}
	kind := stringifyLookup(workload, "kind")
	if kind == "" {
		kind = "Deployment"
	}
	return []Finding{{
		Namespace: namespaceOf(workload),
		Resource:  strings.ToLower(kind) + "/" + stringifyLookup(workload, "metadata.name"),
		Value:     fmt.Sprintf("%d", replicas),
		Message:   "Replicated workload defines neither pod anti-affinity nor topology spread constraints",
	}}
}

func allTemplateWorkloads(cache map[string][]map[string]any) ([]map[string]any, error) {
	var workloads []map[string]any
	for kind, resource := range map[string]string{
		"Deployment":  "deployments",
		"StatefulSet": "statefulsets",
		"DaemonSet":   "daemonsets",
	} {
		items, err := getCachedItems(cache, resource)
		if err != nil {
			return nil, err
		}
		for _, item := range items {
			item["kind"] = kind
			workloads = append(workloads, item)
		}
	}
	return workloads, nil
}

func dedupeFindings(in []Finding) []Finding {
	seen := map[string]bool{}
	out := make([]Finding, 0, len(in))
	for _, finding := range in {
		key := finding.Namespace + "\x00" + finding.Resource + "\x00" + finding.Value + "\x00" + finding.Message
		if seen[key] {
			continue
		}
		seen[key] = true
		out = append(out, finding)
	}
	return out
}

func containersFromTemplate(item map[string]any) []map[string]any {
	return containerList(mustResolve(item, "spec.template.spec.containers"))
}

func initContainersFromTemplate(item map[string]any) []map[string]any {
	return containerList(mustResolve(item, "spec.template.spec.initContainers"))
}

func containerList(value any) []map[string]any {
	var out []map[string]any
	for _, v := range asSlice(value) {
		if m, ok := v.(map[string]any); ok {
			out = append(out, m)
		}
	}
	return out
}

func isInitContainer(item map[string]any, container map[string]any) bool {
	name := stringifyLookup(container, "name")
	for _, c := range initContainersFromTemplate(item) {
		if stringifyLookup(c, "name") == name {
			return true
		}
	}
	return false
}

func addMountedRefNames(used map[string]bool, item map[string]any, volumeField string, path string) {
	for _, volume := range asSlice(mustResolve(item, "spec.volumes")) {
		if mustResolve(volume, volumeField) != nil {
			if name := stringifyLookup(volume, path); name != "" {
				used[name] = true
			}
		}
	}
}

func addContainerRefs(used map[string]bool, item map[string]any, envPath string, envFromPath string) {
	for _, container := range allContainers(item) {
		for _, env := range asSlice(mustResolve(container, "env")) {
			if name := stringifyLookup(env, "valueFrom."+envPath); name != "" {
				used[name] = true
			}
		}
		for _, envFrom := range asSlice(mustResolve(container, "envFrom")) {
			if name := stringifyLookup(envFrom, envFromPath); name != "" {
				used[name] = true
			}
		}
	}
}

func hpaTargetExists(cache map[string][]map[string]any, ns, targetKind, targetName string) bool {
	var kind string
	switch targetKind {
	case "Deployment":
		kind = "deployments"
	case "StatefulSet":
		kind = "statefulsets"
	default:
		return false
	}
	items, err := getCachedItems(cache, kind)
	if err != nil {
		return false
	}
	for _, item := range items {
		if namespaceOf(item) == ns && stringifyLookup(item, "metadata.name") == targetName {
			return true
		}
	}
	return false
}

func selectorMatchesLabels(selector any, labelsAny any) bool {
	labels, _ := labelsAny.(map[string]any)
	sel, _ := selector.(map[string]any)
	if len(sel) == 0 {
		return false
	}
	for k, v := range sel {
		if fmt.Sprint(labels[k]) != fmt.Sprint(v) {
			return false
		}
	}
	return true
}

func selectorOverlaps(selector any, labelsAny any) bool {
	labels, _ := labelsAny.(map[string]any)
	sel, _ := selector.(map[string]any)
	if len(sel) == 0 || len(labels) == 0 {
		return false
	}
	for k, v := range sel {
		if fmt.Sprint(labels[k]) == fmt.Sprint(v) {
			return true
		}
	}
	return false
}

func jobComplete(item map[string]any) bool {
	for _, c := range asSlice(mustResolve(item, "status.conditions")) {
		if stringifyLookup(c, "type") == "Complete" && stringifyLookup(c, "status") == "True" {
			return true
		}
	}
	return false
}

func parseTime(value string) time.Time {
	if strings.TrimSpace(value) == "" {
		return time.Time{}
	}
	t, err := time.Parse(time.RFC3339, value)
	if err != nil {
		return time.Time{}
	}
	return t
}

func asInt64(value any) int64 {
	switch v := value.(type) {
	case int:
		return int64(v)
	case int32:
		return int64(v)
	case int64:
		return v
	case float64:
		return int64(v)
	case string:
		var out int64
		fmt.Sscan(v, &out)
		return out
	default:
		return 0
	}
}

func rbacMisconfigFindings(cache map[string][]map[string]any) ([]Finding, error) {
	roleBindings, err := getCachedItems(cache, "rolebindings")
	if err != nil {
		return nil, err
	}
	clusterRoleBindings, err := getCachedItems(cache, "clusterrolebindings")
	if err != nil {
		return nil, err
	}
	roles, err := getCachedItems(cache, "roles")
	if err != nil {
		return nil, err
	}
	clusterRoles, err := getCachedItems(cache, "clusterroles")
	if err != nil {
		return nil, err
	}
	namespaces, err := getCachedItems(cache, "namespaces")
	if err != nil {
		return nil, err
	}
	serviceAccounts, err := getCachedItems(cache, "serviceaccounts")
	if err != nil {
		return nil, err
	}
	nsSet := map[string]bool{}
	for _, ns := range namespaces {
		nsSet[stringifyLookup(ns, "metadata.name")] = true
	}
	roleSet := map[string]bool{}
	for _, role := range roles {
		roleSet[namespaceOf(role)+"/"+stringifyLookup(role, "metadata.name")] = true
	}
	clusterRoleSet := map[string]bool{}
	for _, role := range clusterRoles {
		clusterRoleSet[stringifyLookup(role, "metadata.name")] = true
	}
	saSet := map[string]bool{}
	for _, sa := range serviceAccounts {
		saSet[namespaceOf(sa)+"/"+stringifyLookup(sa, "metadata.name")] = true
	}
	var findings []Finding
	for _, rb := range roleBindings {
		ns := namespaceOf(rb)
		name := stringifyLookup(rb, "metadata.name")
		roleRef := mustResolve(rb, "roleRef")
		if roleRef == nil {
			findings = append(findings, Finding{Namespace: ns, Resource: "rolebinding/" + name, Value: "-", Message: "Missing roleRef in RoleBinding"})
			continue
		}
		refKind := stringifyLookup(rb, "roleRef.kind")
		refName := stringifyLookup(rb, "roleRef.name")
		if refKind == "Role" && !roleSet[ns+"/"+refName] {
			findings = append(findings, Finding{Namespace: ns, Resource: "rolebinding/" + name, Value: refName, Message: "Missing Role: " + refName})
		}
		if refKind == "ClusterRole" {
			findings = append(findings, Finding{Namespace: ns, Resource: "rolebinding/" + name, Value: refName, Message: "RoleBinding references ClusterRole"})
		}
		for _, subject := range asSlice(mustResolve(rb, "subjects")) {
			if stringifyLookup(subject, "kind") != "ServiceAccount" {
				continue
			}
			subjectNS := stringifyLookup(subject, "namespace")
			if subjectNS == "" {
				subjectNS = ns
			}
			if isExcludedNamespace(subjectNS) {
				continue
			}
			subjectName := stringifyLookup(subject, "name")
			if !nsSet[subjectNS] {
				findings = append(findings, Finding{Namespace: "(unknown)", Resource: "rolebinding/" + name, Value: "ServiceAccount/" + subjectName, Message: "Namespace does not exist: " + subjectNS})
			} else if !saSet[subjectNS+"/"+subjectName] {
				findings = append(findings, Finding{Namespace: subjectNS, Resource: "rolebinding/" + name, Value: "ServiceAccount/" + subjectName, Message: "ServiceAccount not found"})
			}
		}
	}
	for _, crb := range clusterRoleBindings {
		name := stringifyLookup(crb, "metadata.name")
		if mustResolve(crb, "roleRef") == nil {
			findings = append(findings, Finding{Namespace: "(cluster)", Resource: "clusterrolebinding/" + name, Value: "-", Message: "Missing roleRef in ClusterRoleBinding"})
			continue
		}
		roleName := stringifyLookup(crb, "roleRef.name")
		if roleName != "" && !clusterRoleSet[roleName] {
			findings = append(findings, Finding{Namespace: "(cluster)", Resource: "clusterrolebinding/" + name, Value: roleName, Message: "Missing ClusterRole: " + roleName})
		}
		for _, subject := range asSlice(mustResolve(crb, "subjects")) {
			if stringifyLookup(subject, "kind") != "ServiceAccount" {
				continue
			}
			subjectNS := stringifyLookup(subject, "namespace")
			subjectName := stringifyLookup(subject, "name")
			if subjectNS == "" {
				findings = append(findings, Finding{Namespace: "(cluster)", Resource: "clusterrolebinding/" + name, Value: "ServiceAccount/" + subjectName, Message: "Missing namespace in ClusterRoleBinding subject"})
				continue
			}
			if isExcludedNamespace(subjectNS) {
				continue
			}
			if !nsSet[subjectNS] {
				findings = append(findings, Finding{Namespace: "(unknown)", Resource: "clusterrolebinding/" + name, Value: "ServiceAccount/" + subjectName, Message: "Namespace does not exist: " + subjectNS})
			} else if !saSet[subjectNS+"/"+subjectName] {
				findings = append(findings, Finding{Namespace: subjectNS, Resource: "clusterrolebinding/" + name, Value: "ServiceAccount/" + subjectName, Message: "ServiceAccount not found"})
			}
		}
	}
	return findings, nil
}

func rbacOverexposureFindings(cache map[string][]map[string]any) ([]Finding, error) {
	roles, err := getCachedItems(cache, "roles")
	if err != nil {
		return nil, err
	}
	clusterRoles, err := getCachedItems(cache, "clusterroles")
	if err != nil {
		return nil, err
	}
	roleBindings, err := getCachedItems(cache, "rolebindings")
	if err != nil {
		return nil, err
	}
	clusterRoleBindings, err := getCachedItems(cache, "clusterrolebindings")
	if err != nil {
		return nil, err
	}
	wildcardRoles := map[string]bool{}
	sensitiveRoles := map[string]bool{}
	builtIn := map[string]bool{"cluster-admin": true, "admin": true, "edit": true, "view": true}
	for _, cr := range clusterRoles {
		name := stringifyLookup(cr, "metadata.name")
		if strings.HasPrefix(name, "system:") || stringifyLookup(cr, "metadata.labels.kubernetes.io/bootstrapping") == "rbac-defaults" {
			builtIn[name] = true
		}
		if roleIsWildcard(cr) {
			wildcardRoles[name] = true
		}
		if roleIsSensitive(cr) {
			sensitiveRoles[name] = true
		}
	}
	for _, r := range roles {
		key := namespaceOf(r) + "/" + stringifyLookup(r, "metadata.name")
		if roleIsWildcard(r) {
			wildcardRoles[key] = true
		}
		if roleIsSensitive(r) {
			sensitiveRoles[key] = true
		}
	}
	var findings []Finding
	for _, crb := range clusterRoleBindings {
		roleName := stringifyLookup(crb, "roleRef.name")
		if roleName != "cluster-admin" && !wildcardRoles[roleName] && !sensitiveRoles[roleName] {
			continue
		}
		for _, subject := range asSlice(mustResolve(crb, "subjects")) {
			value := stringifyLookup(subject, "kind") + "/" + stringifyLookup(subject, "name")
			message := overexposureMessage(roleName, wildcardRoles[roleName], sensitiveRoles[roleName])
			if builtIn[roleName] {
				message += " (built-in)"
			}
			if stringifyLookup(subject, "kind") == "ServiceAccount" && stringifyLookup(subject, "name") == "default" {
				message += " (default ServiceAccount)"
			}
			findings = append(findings, Finding{Namespace: "🌍 Cluster-Wide", Resource: "clusterrolebinding/" + stringifyLookup(crb, "metadata.name"), Value: value, Message: message})
		}
	}
	for _, rb := range roleBindings {
		ns := namespaceOf(rb)
		roleName := stringifyLookup(rb, "roleRef.name")
		key := ns + "/" + roleName
		if roleName != "cluster-admin" && !wildcardRoles[key] && !sensitiveRoles[key] {
			continue
		}
		for _, subject := range asSlice(mustResolve(rb, "subjects")) {
			value := stringifyLookup(subject, "kind") + "/" + stringifyLookup(subject, "name")
			message := overexposureMessage(roleName, wildcardRoles[key], sensitiveRoles[key])
			if builtIn[roleName] {
				message += " (built-in)"
			}
			if stringifyLookup(subject, "kind") == "ServiceAccount" && stringifyLookup(subject, "name") == "default" {
				message += " (default ServiceAccount)"
			}
			findings = append(findings, Finding{Namespace: ns, Resource: "rolebinding/" + stringifyLookup(rb, "metadata.name"), Value: value, Message: message})
		}
	}
	return findings, nil
}

func orphanedRoles(cache map[string][]map[string]any) ([]Finding, error) {
	roles, err := getCachedItems(cache, "roles")
	if err != nil {
		return nil, err
	}
	clusterRoles, err := getCachedItems(cache, "clusterroles")
	if err != nil {
		return nil, err
	}
	roleBindings, err := getCachedItems(cache, "rolebindings")
	if err != nil {
		return nil, err
	}
	clusterRoleBindings, err := getCachedItems(cache, "clusterrolebindings")
	if err != nil {
		return nil, err
	}
	used := map[string]bool{}
	var findings []Finding
	for _, rb := range roleBindings {
		refKind := stringifyLookup(rb, "roleRef.kind")
		refName := stringifyLookup(rb, "roleRef.name")
		if refKind == "Role" {
			used[namespaceOf(rb)+"/"+refName] = true
		} else if refKind == "ClusterRole" {
			used[refName] = true
		}
		if len(asSlice(mustResolve(rb, "subjects"))) == 0 {
			findings = append(findings, Finding{Namespace: namespaceOf(rb), Resource: "rolebinding/" + stringifyLookup(rb, "metadata.name"), Value: refName, Message: "RoleBinding has no subjects"})
		}
	}
	for _, crb := range clusterRoleBindings {
		refName := stringifyLookup(crb, "roleRef.name")
		if refName != "" {
			used[refName] = true
		}
		if len(asSlice(mustResolve(crb, "subjects"))) == 0 {
			findings = append(findings, Finding{Namespace: "cluster-wide", Resource: "clusterrolebinding/" + stringifyLookup(crb, "metadata.name"), Value: refName, Message: "ClusterRoleBinding has no subjects"})
		}
	}
	for _, role := range roles {
		key := namespaceOf(role) + "/" + stringifyLookup(role, "metadata.name")
		if used[key] {
			continue
		}
		msg := "Role is not referenced by any RoleBinding"
		if len(asSlice(mustResolve(role, "rules"))) == 0 {
			msg = "Role defines no rules"
		}
		findings = append(findings, Finding{Namespace: namespaceOf(role), Resource: "role/" + stringifyLookup(role, "metadata.name"), Value: "", Message: msg})
	}
	for _, role := range clusterRoles {
		key := stringifyLookup(role, "metadata.name")
		if isBuiltInClusterRole(role) {
			if len(asSlice(mustResolve(role, "rules"))) == 0 {
				findings = append(findings, Finding{Namespace: "cluster-wide", Resource: "clusterrole/" + key, Value: key, Message: "ClusterRole has no rules"})
			}
			continue
		}
		if used[key] {
			if len(asSlice(mustResolve(role, "rules"))) == 0 {
				findings = append(findings, Finding{Namespace: "cluster-wide", Resource: "clusterrole/" + key, Value: key, Message: "ClusterRole has no rules"})
			}
			continue
		}
		msg := "Unused ClusterRole"
		if len(asSlice(mustResolve(role, "rules"))) == 0 {
			msg = "ClusterRole defines no rules"
		}
		findings = append(findings, Finding{Namespace: "cluster-wide", Resource: "clusterrole/" + key, Value: key, Message: msg})
	}
	return findings, nil
}

func isExcludedNamespace(ns string) bool {
	ns = strings.ToLower(strings.TrimSpace(ns))
	if ns == "" {
		return false
	}
	_, ok := currentRuntime.Excluded[ns]
	return ok
}

func isBuiltInClusterRole(role map[string]any) bool {
	name := stringifyLookup(role, "metadata.name")
	if name == "cluster-admin" || name == "admin" || name == "edit" || name == "view" || name == "system:public-info-viewer" {
		return true
	}
	if strings.HasPrefix(name, "system:") || strings.HasPrefix(name, "system:kube-") || strings.HasPrefix(name, "system:node") {
		return true
	}
	return stringifyLookup(role, "metadata.labels.kubernetes.io/bootstrapping") == "rbac-defaults"
}

func roleIsWildcard(role map[string]any) bool {
	for _, rule := range asSlice(mustResolve(role, "rules")) {
		if containsString(asSlice(mustResolve(rule, "verbs")), "*") &&
			containsString(asSlice(mustResolve(rule, "resources")), "*") &&
			containsString(asSlice(mustResolve(rule, "apiGroups")), "*") {
			return true
		}
	}
	return false
}

func roleIsSensitive(role map[string]any) bool {
	sensitive := map[string]bool{"secrets": true, "pods/exec": true, "roles": true, "clusterroles": true, "bindings": true, "clusterrolebindings": true}
	dangerous := map[string]bool{"*": true, "create": true, "update": true, "delete": true}
	for _, rule := range asSlice(mustResolve(role, "rules")) {
		hasSensitive := false
		for _, r := range asSlice(mustResolve(rule, "resources")) {
			if sensitive[fmt.Sprint(r)] {
				hasSensitive = true
				break
			}
		}
		if !hasSensitive {
			continue
		}
		for _, v := range asSlice(mustResolve(rule, "verbs")) {
			if dangerous[fmt.Sprint(v)] {
				return true
			}
		}
	}
	return false
}

func overexposureMessage(roleName string, wildcard bool, sensitive bool) string {
	switch {
	case roleName == "cluster-admin":
		return "cluster-admin binding"
	case wildcard:
		return "Wildcard permission role"
	case sensitive:
		return "Access to sensitive resources"
	default:
		return "RBAC overexposure"
	}
}

func containsString(values []any, expected string) bool {
	for _, value := range values {
		if fmt.Sprint(value) == expected {
			return true
		}
	}
	return false
}

func joinAny(values []any, sep string) string {
	parts := make([]string, 0, len(values))
	for _, value := range values {
		parts = append(parts, fmt.Sprint(value))
	}
	return strings.Join(parts, sep)
}

func selectorKey(value any) string {
	selector, _ := value.(map[string]any)
	if len(selector) == 0 {
		return ""
	}
	keys := make([]string, 0, len(selector))
	for key := range selector {
		keys = append(keys, key)
	}
	sort.Strings(keys)
	parts := make([]string, 0, len(keys))
	for _, key := range keys {
		parts = append(parts, key+"="+fmt.Sprint(selector[key]))
	}
	return strings.Join(parts, ";")
}

func selectorJSON(value any) string {
	data, err := json.Marshal(value)
	if err != nil {
		return ""
	}
	return string(data)
}

func looksLikeIPv4(value string) bool {
	ip := net.ParseIP(strings.TrimSpace(value))
	return ip != nil && ip.To4() != nil
}

func isInternalIP(value string) bool {
	ip := net.ParseIP(strings.TrimSpace(value))
	if ip == nil {
		return false
	}
	privateCIDRs := []string{
		"10.0.0.0/8",
		"172.16.0.0/12",
		"192.168.0.0/16",
		"127.0.0.0/8",
		"169.254.0.0/16",
		"100.64.0.0/10",
		"0.0.0.0/8",
	}
	for _, cidr := range privateCIDRs {
		_, network, _ := net.ParseCIDR(cidr)
		if network.Contains(ip) {
			return true
		}
	}
	return false
}

func resolveIntOrPercent(raw any, replicas int64) *int64 {
	if raw == nil {
		return nil
	}
	text := fmt.Sprint(raw)
	if strings.HasSuffix(text, "%") {
		var pct int64
		fmt.Sscan(strings.TrimSuffix(text, "%"), &pct)
		value := int64((float64(replicas*pct) + 99) / 100)
		return &value
	}
	value := asInt64(raw)
	return &value
}

func resolveTargetWorkload(cache map[string][]map[string]any, ns, targetKind, targetName string) (map[string]any, error) {
	var resource string
	switch targetKind {
	case "Deployment":
		resource = "deployments"
	case "StatefulSet":
		resource = "statefulsets"
	default:
		return nil, nil
	}
	items, err := getCachedItems(cache, resource)
	if err != nil {
		return nil, err
	}
	for _, item := range items {
		if namespaceOf(item) == ns && stringifyLookup(item, "metadata.name") == targetName {
			return item, nil
		}
	}
	return nil, nil
}

func findCondition(conditions []any, conditionType string) any {
	for _, condition := range conditions {
		if stringifyLookup(condition, "type") == conditionType {
			return condition
		}
	}
	return nil
}

func secretExists(secrets []map[string]any, ns, name string) bool {
	for _, secret := range secrets {
		if namespaceOf(secret) == ns && stringifyLookup(secret, "metadata.name") == name {
			return true
		}
	}
	return false
}

func hasReferenceGrant(grants []map[string]any, fromNamespace, toNamespace, secretName string) bool {
	for _, grant := range grants {
		if namespaceOf(grant) != toNamespace {
			continue
		}
		fromAllowed := false
		for _, from := range asSlice(mustResolve(grant, "spec.from")) {
			group := stringifyLookup(from, "group")
			kind := stringifyLookup(from, "kind")
			ns := stringifyLookup(from, "namespace")
			groupOk := group == "" || group == "gateway.networking.k8s.io"
			kindOk := kind == "" || kind == "Gateway"
			nsOk := ns == "" || ns == fromNamespace
			if groupOk && kindOk && nsOk {
				fromAllowed = true
				break
			}
		}
		if !fromAllowed {
			continue
		}
		for _, to := range asSlice(mustResolve(grant, "spec.to")) {
			group := stringifyLookup(to, "group")
			kind := stringifyLookup(to, "kind")
			name := stringifyLookup(to, "name")
			groupOk := group == ""
			kindOk := kind == "" || kind == "Secret"
			nameOk := name == "" || name == secretName
			if groupOk && kindOk && nameOk {
				return true
			}
		}
	}
	return false
}

func serviceByName(services []map[string]any, ns, name string) map[string]any {
	for _, svc := range services {
		if namespaceOf(svc) == ns && stringifyLookup(svc, "metadata.name") == name {
			return svc
		}
	}
	return nil
}

func serviceHasPort(service map[string]any, target string) bool {
	for _, port := range asSlice(mustResolve(service, "spec.ports")) {
		if stringifyLookup(port, "port") == target || stringifyLookup(port, "name") == target || stringifyLookup(port, "targetPort") == target {
			return true
		}
	}
	return false
}

func serviceTargetPortMatchesPods(targetPort string, pods []map[string]any) bool {
	for _, pod := range pods {
		for _, container := range containersOnly(pod) {
			for _, port := range asSlice(mustResolve(container, "ports")) {
				if stringifyLookup(port, "name") == targetPort || stringifyLookup(port, "containerPort") == targetPort {
					return true
				}
			}
		}
	}
	return false
}

type topNodeRow struct {
	CPUPct  float64
	MemPct  float64
	DiskPct float64
}

func parseTopNodes() (map[string]topNodeRow, error) {
	if currentRuntime.KubeClient == nil {
		return nil, fmt.Errorf("kubernetes client not configured")
	}
	items, err := currentRuntime.KubeClient.List(currentRuntime.KubeContext, "nodes", false)
	if err != nil {
		return nil, err
	}
	metrics, err := currentRuntime.KubeClient.NodeMetrics(currentRuntime.KubeContext)
	if err != nil {
		return nil, err
	}
	rows := map[string]topNodeRow{}
	for _, node := range items {
		name := stringifyLookup(node, "metadata.name")
		if name == "" {
			continue
		}
		metric, ok := metrics[name]
		if !ok {
			continue
		}
		row := topNodeRow{
			CPUPct: percentOf(metric.CPUMilli, milliCPUCapacity(node)),
			MemPct: percentOf(metric.MemBytes, memoryCapacityBytes(node)),
		}
		rows[name] = row
	}
	return rows, nil
}

func percentOf(used int64, total int64) float64 {
	if used <= 0 || total <= 0 {
		return 0
	}
	return (float64(used) / float64(total)) * 100
}

func milliCPUCapacity(node map[string]any) int64 {
	value := strings.TrimSpace(stringifyLookup(node, "status.capacity.cpu"))
	if strings.HasSuffix(value, "m") {
		var out int64
		fmt.Sscan(strings.TrimSuffix(value, "m"), &out)
		return out
	}
	var out int64
	fmt.Sscan(value, &out)
	return out * 1000
}

func memoryCapacityBytes(node map[string]any) int64 {
	value := strings.TrimSpace(strings.ToLower(stringifyLookup(node, "status.capacity.memory")))
	suffixes := []struct {
		unit string
		mult int64
	}{
		{"ki", 1024},
		{"mi", 1024 * 1024},
		{"gi", 1024 * 1024 * 1024},
		{"ti", 1024 * 1024 * 1024 * 1024},
		{"k", 1000},
		{"m", 1000 * 1000},
		{"g", 1000 * 1000 * 1000},
	}
	for _, suffix := range suffixes {
		if strings.HasSuffix(value, suffix.unit) {
			var out int64
			fmt.Sscan(strings.TrimSuffix(value, suffix.unit), &out)
			return out * suffix.mult
		}
	}
	var out int64
	fmt.Sscan(value, &out)
	return out
}

func parsePercent(value string) float64 {
	value = strings.TrimSpace(strings.TrimSuffix(value, "%"))
	var out float64
	fmt.Sscan(value, &out)
	return out
}

func nodeReady(node map[string]any) bool {
	for _, condition := range asSlice(mustResolve(node, "status.conditions")) {
		if stringifyLookup(condition, "type") == "Ready" && stringifyLookup(condition, "status") == "True" {
			return true
		}
	}
	return false
}

func appendContainerSets(item map[string]any) []map[string]any {
	return collectContainers(item, true)
}

func allContainers(item map[string]any) []map[string]any {
	return collectContainers(item, false)
}

func containersOnly(item map[string]any) []map[string]any {
	value := mustResolve(item, "spec.containers")
	values := asSlice(value)
	var out []map[string]any
	for _, value := range values {
		if m, ok := value.(map[string]any); ok {
			out = append(out, m)
		}
	}
	return out
}

func collectContainers(item map[string]any, includeMissingSlots bool) []map[string]any {
	var out []map[string]any
	for _, path := range []string{
		"spec.containers",
		"spec.initContainers",
		"spec.ephemeralContainers",
	} {
		value := mustResolve(item, path)
		values := asSlice(value)
		if includeMissingSlots && value == nil {
			// Match the legacy PowerShell concatenation behavior, which appends a null slot
			// for missing init/ephemeral container arrays and then counts it as a root-default hit.
			out = append(out, map[string]any{})
			continue
		}
		for _, value := range values {
			if m, ok := value.(map[string]any); ok {
				out = append(out, m)
			}
		}
	}
	return out
}

func readRunAsUser(item any, path string) (int64, bool) {
	value := mustResolve(item, path)
	switch v := value.(type) {
	case int:
		return int64(v), true
	case int64:
		return v, true
	case float64:
		return int64(v), true
	default:
		return 0, false
	}
}

func readBool(item any, path string) (bool, bool) {
	value := mustResolve(item, path)
	if value == nil {
		return false, false
	}
	if flag, ok := value.(bool); ok {
		return flag, true
	}
	return false, false
}

func stringifyLookup(item any, path string) string {
	value := mustResolve(item, path)
	if value == nil {
		return ""
	}
	return fmt.Sprint(value)
}

func mustResolve(item any, path string) any {
	value, _ := checks.ResolvePath(item, path)
	return value
}

func formatBoolPointer(present bool, value bool) string {
	if !present {
		return ""
	}
	if value {
		return "True"
	}
	return "False"
}

func asSlice(value any) []any {
	if value == nil {
		return nil
	}
	v := reflect.ValueOf(value)
	for v.Kind() == reflect.Pointer || v.Kind() == reflect.Interface {
		if v.IsNil() {
			return nil
		}
		v = v.Elem()
	}
	if v.Kind() != reflect.Slice && v.Kind() != reflect.Array {
		return []any{value}
	}
	out := make([]any, 0, v.Len())
	for i := 0; i < v.Len(); i++ {
		out = append(out, v.Index(i).Interface())
	}
	return out
}
