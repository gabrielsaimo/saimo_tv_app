import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../utils/theme.dart';
import '../utils/tv_constants.dart';

class UpdateDialog extends StatelessWidget {
  final String currentVersion;
  final String newVersion;
  final bool forceUpdate;

  const UpdateDialog({
    super.key,
    required this.currentVersion,
    required this.newVersion,
    this.forceUpdate = true,
  });

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final isCompact = size.height < 600 || size.width < 400;
    
    return WillPopScope(
      onWillPop: () async => !forceUpdate,
      child: Dialog(
        backgroundColor: SaimoTheme.surface,
        insetPadding: EdgeInsets.symmetric(
          horizontal: isCompact ? 16 : 40,
          vertical: isCompact ? 24 : 40,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: SaimoTheme.primary, width: 2),
        ),
        child: Container(
          constraints: BoxConstraints(
            maxWidth: isCompact ? size.width * 0.92 : 500,
            maxHeight: size.height * 0.85,
          ),
          child: SingleChildScrollView(
            padding: EdgeInsets.all(isCompact ? 20 : 32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.system_update,
                  size: isCompact ? 56 : 80,
                  color: SaimoTheme.primary,
                ),
                SizedBox(height: isCompact ? 16 : 24),
                Text(
                  'Nova Versão Disponível',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: isCompact ? 20 : 28,
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ),
                SizedBox(height: isCompact ? 12 : 16),
                Text(
                  'Uma nova versão do Saimo TV está disponível.\nPor favor, atualize para continuar.',
                  style: TextStyle(
                    color: SaimoTheme.textSecondary,
                    fontSize: isCompact ? 14 : 18,
                  ),
                  textAlign: TextAlign.center,
                ),
                SizedBox(height: isCompact ? 16 : 24),
                Container(
                  padding: EdgeInsets.symmetric(
                    horizontal: isCompact ? 12 : 24,
                    vertical: isCompact ? 8 : 12,
                  ),
                  decoration: BoxDecoration(
                    color: SaimoTheme.surfaceLight,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: isCompact
                      // Layout vertical para telas pequenas
                      ? Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _buildVersionBadge('Versão Atual', currentVersion, Colors.grey, isCompact),
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              child: Icon(Icons.arrow_downward, color: Colors.white, size: 20),
                            ),
                            _buildVersionBadge('Nova Versão', newVersion, SaimoTheme.success, isCompact),
                          ],
                        )
                      // Layout horizontal para telas grandes
                      : Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _buildVersionBadge('Versão Atual', currentVersion, Colors.grey, isCompact),
                            const Padding(
                              padding: EdgeInsets.symmetric(horizontal: 16),
                              child: Icon(Icons.arrow_forward, color: Colors.white),
                            ),
                            _buildVersionBadge('Nova Versão', newVersion, SaimoTheme.success, isCompact),
                          ],
                        ),
                ),
                SizedBox(height: isCompact ? 20 : 32),
                SizedBox(
                  width: double.infinity,
                  height: isCompact ? 44 : 50,
                  child: ElevatedButton(
                    onPressed: () => _launchUpdateUrl(context),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: SaimoTheme.primary,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: Text(
                      'ATUALIZAR AGORA',
                      style: TextStyle(
                        fontSize: isCompact ? 14 : 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              if (!forceUpdate)
                  Padding(
                    padding: EdgeInsets.only(top: isCompact ? 12 : 16),
                    child: TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: Text(
                        'Lembrar depois',
                        style: TextStyle(
                          color: SaimoTheme.textTertiary,
                          fontSize: isCompact ? 12 : 14,
                        ),
                      ),
                    ),
                  )
                else
                  Padding(
                    padding: EdgeInsets.only(top: isCompact ? 12 : 16),
                    child: TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: Text(
                        'Fechar',
                        style: TextStyle(
                          color: SaimoTheme.textTertiary,
                          fontSize: isCompact ? 12 : 14,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }


  Widget _buildVersionBadge(String label, String version, Color color, bool isCompact) {
    return Column(
      children: [
        Text(
          label,
          style: TextStyle(
            color: SaimoTheme.textTertiary,
            fontSize: isCompact ? 10 : 12,
          ),
        ),
        SizedBox(height: isCompact ? 2 : 4),
        Text(
          version,
          style: TextStyle(
            color: color,
            fontSize: isCompact ? 14 : 18,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }


  Future<void> _launchUpdateUrl(BuildContext context) async {
    const url = 'https://saimo-tv.vercel.app/app';
    try {
      if (await canLaunchUrl(Uri.parse(url))) {
        await launchUrl(
          Uri.parse(url),
          mode: LaunchMode.externalApplication,
        );
      } else {
         if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Erro ao abrir link de atualização'),
                backgroundColor: Colors.red,
              ),
            );
        }
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
}
