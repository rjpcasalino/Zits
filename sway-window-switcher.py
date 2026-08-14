#!/usr/bin/env python3
import json
import subprocess
import sys

def main():
    try:
        tree_raw = subprocess.check_output(['swaymsg', '-t', 'get_tree'])
        tree = json.loads(tree_raw)
    except Exception:
        sys.exit(1)

    def find_windows(node, ws_name=''):
        windows = []
        if node.get('type') == 'workspace':
            ws_name = node.get('name', '')
        if node.get('name') and (node.get('app_id') or node.get('window_properties')):
            title = node.get('name', 'Untitled')
            app = node.get('app_id') or node.get('window_properties', {}).get('class', 'Unknown')
            con_id = node.get('id')
            windows.append(f"[{ws_name}] {app}: {title} | id={con_id}")
        for child in node.get('nodes', []) + node.get('floating_nodes', []):
            windows.extend(find_windows(child, ws_name))
        return windows

    windows = find_windows(tree)
    if not windows:
        sys.exit(0)

    input_str = '\n'.join(windows)
    try:
        proc = subprocess.Popen(['wofi', '--dmenu', '-p', 'windows:'], stdin=subprocess.PIPE, stdout=subprocess.PIPE, text=True)
        selected, _ = proc.communicate(input=input_str)
        if selected and 'id=' in selected:
            con_id = selected.strip().split('id=')[-1]
            subprocess.run(['swaymsg', f'[con_id={con_id}] focus'])
    except Exception:
        pass

if __name__ == '__main__':
    main()
