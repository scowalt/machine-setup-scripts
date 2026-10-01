# Separate BB preparation from enrollment

BB preparation installs software; it does not authorize association with a server. Setup uses a separate, owned npm prefix outside global command paths, avoiding both command shadowing and becoming the manual enrollment installer's global-package fallback. Server selection and enrollment remain manual, and the upstream installer/updater owns the enrolled machine's private package and startup service rather than having later setup update or convert that role.

This means keeping a separate preparation copy and deferring when an existing role is detected, without claiming readiness. See `setup_bb_machine` in [ubuntu.sh](../../ubuntu.sh) and the [preparation contracts](../../tests/test_bb_machine_preparation.py).
