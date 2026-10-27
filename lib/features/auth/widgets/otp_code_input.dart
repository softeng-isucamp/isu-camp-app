import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// One native input supports paste and OS autofill, with six visible digit boxes.
class OtpCodeInput extends StatefulWidget {
  const OtpCodeInput({
    super.key,
    required this.controller,
    required this.onCompleted,
    required this.onActivity,
    this.enabled = true,
    this.busy = false,
    this.error,
  });

  final TextEditingController controller;
  final ValueChanged<String> onCompleted;
  final VoidCallback onActivity;
  final bool enabled;
  final bool busy;
  final String? error;

  @override
  State<OtpCodeInput> createState() => _OtpCodeInputState();
}

class _OtpCodeInputState extends State<OtpCodeInput> {
  final _focus = FocusNode();

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            height: 54,
            child: Stack(
              children: [
                ValueListenableBuilder<TextEditingValue>(
                  valueListenable: widget.controller,
                  builder: (context, value, _) => Row(
                    children: List.generate(
                        6,
                        (index) => Expanded(
                              child: Container(
                                margin:
                                    EdgeInsets.only(right: index == 5 ? 0 : 8),
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                  color: const Color(0xFFF1F3F2),
                                  borderRadius: BorderRadius.circular(9),
                                  border: Border.all(
                                    color: widget.error != null
                                        ? Colors.redAccent
                                        : _focus.hasFocus &&
                                                index == value.text.length
                                            ? const Color(0xFF0F751B)
                                            : const Color(0xFFD6DED8),
                                  ),
                                ),
                                child: ExcludeSemantics(
                                    child: Text(
                                  index < value.text.length
                                      ? value.text[index]
                                      : '',
                                  style: const TextStyle(
                                      fontSize: 22,
                                      fontWeight: FontWeight.w600),
                                )),
                              ),
                            )),
                  ),
                ),
                TextField(
                  key: const ValueKey('otp_code_input'),
                  controller: widget.controller,
                  focusNode: _focus,
                  autofocus: true,
                  enabled: widget.enabled && !widget.busy,
                  autofillHints: const [AutofillHints.oneTimeCode],
                  keyboardType: TextInputType.number,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(6)
                  ],
                  style:
                      const TextStyle(color: Colors.transparent, fontSize: 22),
                  cursorColor: Colors.transparent,
                  enableInteractiveSelection: false,
                  decoration: const InputDecoration(
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    disabledBorder: InputBorder.none,
                    filled: false,
                    counterText: '',
                    semanticCounterText: '6-digit verification code',
                  ),
                  onTap: () {
                    if (widget.controller.text.length == 6) {
                      widget.controller.selection =
                          const TextSelection(baseOffset: 0, extentOffset: 6);
                    }
                    setState(() {});
                  },
                  onChanged: (code) {
                    widget.onActivity();
                    setState(() {});
                    if (code.length == 6) widget.onCompleted(code);
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          if (widget.busy)
            const Row(children: [
              SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2)),
              SizedBox(width: 10),
              Text('Verifying code…'),
            ])
          else if (widget.error != null)
            Text(widget.error!,
                style: const TextStyle(color: Colors.redAccent),
                semanticsLabel: widget.error)
          else
            const Text('Your code will be verified automatically.',
                style: TextStyle(fontSize: 12, color: Colors.black54)),
        ],
      );
}
