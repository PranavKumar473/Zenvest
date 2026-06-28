import os
import re

for root, dirs, files in os.walk('app'):
    for file in files:
        if file.endswith('.py'):
            filepath = os.path.join(root, file)
            with open(filepath, 'r') as f:
                content = f.read()
            
            if '| None' in content:
                # Add import if needed
                if 'from typing import ' in content:
                    if 'Optional' not in content:
                        content = content.replace('from typing import ', 'from typing import Optional, ')
                else:
                    content = 'from typing import Optional\n' + content
                
                # Replace Type | None with Optional[Type]
                # Regex to match word or word[word] followed by | None
                # e.g. str | None, dict | None, list[str] | None
                content = re.sub(r'([a-zA-Z0-9_]+(?:\[[a-zA-Z0-9_]+\])?)\s*\|\s*None', r'Optional[\1]', content)
                
                with open(filepath, 'w') as f:
                    f.write(content)
