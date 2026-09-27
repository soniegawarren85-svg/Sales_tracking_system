import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';
import 'package:web/web.dart' as web;

/// Reserve the preview during the button click, before PDF generation yields.
/// The browser's PDF viewer supplies printing without a CDN or hidden iframe.
Future<void> printReportDocument({
  required String name,
  required Future<Uint8List> Function() build,
}) async {
  final preview = web.window.open('', '_blank', 'popup,width=1100,height=800');
  if (preview == null) {
    throw StateError('Allow pop-ups for this site, then press Print report again.');
  }
  final document = preview.document;
  document.title = name;
  final body = document.body!;
  body.setAttribute('style', 'margin:0;height:100vh;display:flex;flex-direction:column;font:14px Arial,sans-serif;background:#f6f7f9');
  final toolbar = document.createElement('header')
    ..setAttribute('style', 'display:flex;align-items:center;gap:16px;padding:16px;background:#70132e;color:white;flex-wrap:wrap');
  final heading = document.createElement('strong')..textContent = name;
  final button = document.createElement('button') as web.HTMLButtonElement
    ..textContent = 'Print'
    ..disabled = true;
  button.setAttribute('style', 'padding:10px 20px;border:0;border-radius:8px;cursor:pointer');
  final download = document.createElement('a') as web.HTMLAnchorElement
    ..textContent = 'Download PDF'
    ..download = name;
  download.setAttribute('style', 'color:white;display:none');
  final status = document.createElement('p')
    ..textContent = 'Preparing report…'
    ..setAttribute('style', 'padding:0 16px');
  toolbar.appendChild(heading);
  toolbar.appendChild(button);
  toolbar.appendChild(download);
  body.appendChild(toolbar);
  body.appendChild(status);
  String? url;
  try {
    final bytes = await build();
    if (preview.closed) return;
    if (bytes.isEmpty) throw StateError('The report is empty.');
    url = web.URL.createObjectURL(web.Blob([bytes.toJS].toJS, web.BlobPropertyBag(type: 'application/pdf')));
    download.href = url;
    download.style.display = 'inline';
    final frame = document.createElement('iframe') as web.HTMLIFrameElement
      ..title = 'Report print preview'
      ..setAttribute('style', 'width:100%;flex:1;border:0;min-height:400px');
    void printDocument() {
      try {
        frame.contentWindow?.focus();
        frame.contentWindow?.print();
        status.textContent = 'If the print dialog did not open, use the print icon in the PDF toolbar or Download PDF.';
      } catch (_) {
        status.textContent = 'Use the print icon in the PDF toolbar, or download the PDF and print it.';
      }
    }
    button.addEventListener('click', ((web.Event _) => printDocument()).toJS);
    frame.addEventListener('load', ((web.Event _) {
      button.disabled = false;
      status.textContent = 'Report ready. Use Print or the PDF toolbar to choose your printer.';
      Timer(const Duration(milliseconds: 700), () {
        if (!preview.closed) printDocument();
      });
    }).toJS);
    frame.src = url;
    body.appendChild(frame);
    // Some native PDF viewers do not dispatch load; leave a usable button.
    button.disabled = false;
    status.textContent = 'Report ready. Use Print or the PDF toolbar to choose your printer.';
    Timer.periodic(const Duration(seconds: 2), (timer) {
      if (preview.closed) {
        web.URL.revokeObjectURL(url!);
        timer.cancel();
      }
    });
  } catch (error) {
    if (url != null) web.URL.revokeObjectURL(url);
    if (!preview.closed) status.textContent = 'Unable to prepare report: $error';
    rethrow;
  }
}
