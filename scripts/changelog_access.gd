extends RefCounted
## 固定高熵口令仅存盐和摘要；这只是本地界面的访问门槛，不能阻止程序逆向。
const SALT := "6ccfc6783c22b2c22bf8058ff6f812ce"
const DIGEST := "7f52d82a699262afa1a2b96a0f3fbd96ba653104c7f10a69035042241334fe91"

static func verify(password: String) -> bool:
	if password.is_empty() or password.length() > 128:
		return false
	var actual := (SALT + "\n" + password).sha256_buffer()
	var expected := DIGEST.hex_decode()
	var mismatch := 0
	for i in actual.size():
		mismatch |= actual[i] ^ expected[i]
	return mismatch == 0
