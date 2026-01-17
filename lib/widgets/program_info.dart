import 'package:flutter/material.dart';
import '../models/program.dart';
import '../utils/theme.dart';

/// Widget de informações do programa atual - Otimizado para TV
class ProgramInfo extends StatelessWidget {
  final Program? currentProgram;
  final Program? nextProgram;
  final bool compact;
  final bool showNextProgram;

  const ProgramInfo({
    super.key,
    this.currentProgram,
    this.nextProgram,
    this.compact = false,
    this.showNextProgram = true,
  });

  @override
  Widget build(BuildContext context) {
    if (currentProgram == null) {
      return _buildEmpty();
    }

    return compact ? _buildCompact() : _buildFull();
  }

  Widget _buildEmpty() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: SaimoTheme.card,
        borderRadius: BorderRadius.circular(12),
      ),
      child: const Row(
        children: [
          Icon(Icons.tv_off, color: SaimoTheme.textTertiary),
          SizedBox(width: 12),
          Text(
            'Programação indisponível',
            style: TextStyle(
              color: SaimoTheme.textTertiary,
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCompact() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.transparent,
            Colors.black.withOpacity(0.85),
          ],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Programa atual - sem badge AGORA
          Text(
            currentProgram!.title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w600,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          
          const SizedBox(height: 10),
          
          // Barra de progresso maior
          _buildProgressBar(),
          
          const SizedBox(height: 8),
          
          // Horário com mais detalhes
          Row(
            children: [
              const Icon(Icons.schedule, color: Colors.white54, size: 14),
              const SizedBox(width: 4),
              Text(
                currentProgram!.formattedStartTime,
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
              Text(
                ' - ',
                style: TextStyle(color: Colors.white54),
              ),
              Text(
                currentProgram!.formattedEndTime,
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.timer, color: Colors.white70, size: 14),
                    const SizedBox(width: 4),
                    Text(
                      '${currentProgram!.remainingMinutes} min',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          
          // Próximo programa (sempre visível em modo compacto para TV)
          if (showNextProgram && nextProgram != null) ...[
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.1),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.white.withOpacity(0.15)),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: SaimoTheme.primary.withOpacity(0.8),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Text(
                      'A SEGUIR',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          nextProgram!.title,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${nextProgram!.formattedStartTime} - ${nextProgram!.formattedEndTime}',
                          style: const TextStyle(
                            color: Colors.white54,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildFull() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: SaimoTheme.card,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              const Icon(Icons.live_tv, color: SaimoTheme.primary, size: 24),
              const SizedBox(width: 12),
              const Text(
                'Programação',
                style: TextStyle(
                  color: SaimoTheme.textPrimary,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          
          const SizedBox(height: 20),
          
          // Programa atual
          _buildProgramItem(
            currentProgram!,
            isNow: true,
          ),
          
          const SizedBox(height: 12),
          
          // Barra de progresso
          _buildProgressBar(),
          
          const SizedBox(height: 8),
          
          // Tempo restante
          Text(
            '${currentProgram!.remainingMinutes} minutos restantes',
            style: const TextStyle(
              color: SaimoTheme.textTertiary,
              fontSize: 13,
            ),
          ),
          
          // Próximo programa
          if (nextProgram != null) ...[
            const SizedBox(height: 20),
            const Divider(color: SaimoTheme.surfaceLight),
            const SizedBox(height: 16),
            
            _buildProgramItem(
              nextProgram!,
              isNow: false,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildProgramItem(Program program, {required bool isNow}) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Horário em vez de badge
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: isNow ? SaimoTheme.primary.withOpacity(0.2) : SaimoTheme.surfaceLight,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            program.formattedStartTime,
            style: TextStyle(
              color: isNow ? SaimoTheme.primary : SaimoTheme.textSecondary,
              fontSize: 11,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        
        const SizedBox(width: 12),
        
        // Info
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                program.title,
                style: TextStyle(
                  color: isNow ? SaimoTheme.textPrimary : SaimoTheme.textSecondary,
                  fontSize: isNow ? 18 : 15,
                  fontWeight: isNow ? FontWeight.w600 : FontWeight.normal,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              
              const SizedBox(height: 4),
              
              Row(
                children: [
                  Icon(
                    Icons.schedule,
                    size: 14,
                    color: SaimoTheme.textTertiary,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    program.formattedPeriod,
                    style: const TextStyle(
                      color: SaimoTheme.textTertiary,
                      fontSize: 13,
                    ),
                  ),
                  if (program.category != null) ...[
                    const SizedBox(width: 12),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: SaimoTheme.primary.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        program.category!,
                        style: const TextStyle(
                          color: SaimoTheme.primary,
                          fontSize: 11,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
              
              if (program.description != null && program.description!.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  program.description!,
                  style: const TextStyle(
                    color: SaimoTheme.textTertiary,
                    fontSize: 13,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildProgressBar() {
    final progress = currentProgram?.progress ?? 0;
    
    return Container(
      height: 6,
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.2),
        borderRadius: BorderRadius.circular(3),
      ),
      child: FractionallySizedBox(
        alignment: Alignment.centerLeft,
        widthFactor: (progress / 100).clamp(0.0, 1.0),
        child: Container(
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [SaimoTheme.primary, SaimoTheme.accent],
            ),
            borderRadius: BorderRadius.circular(3),
            boxShadow: [
              BoxShadow(
                color: SaimoTheme.primary.withOpacity(0.5),
                blurRadius: 6,
                spreadRadius: 0,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
