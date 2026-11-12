package com.tianzige.tv

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.viewModels
import androidx.compose.runtime.getValue
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.lifecycleScope
import androidx.lifecycle.repeatOnLifecycle
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import com.tianzige.tv.ui.TvRoot
import com.tianzige.tv.ui.theme.TzTheme
import com.tianzige.tv.vm.HomeViewModel

class MainActivity : ComponentActivity() {

    private val viewModel: HomeViewModel by viewModels()

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        lifecycleScope.launch {
            repeatOnLifecycle(Lifecycle.State.STARTED) {
                while (isActive) {
                    delay(4000L)
                    viewModel.refreshIfNeeded(backgroundPoll = true)
                }
            }
        }
        setContent {
            TzTheme {
                val state by viewModel.state.collectAsStateWithLifecycle()
                TvRoot(state = state, vm = viewModel, onExit = { finish() })
            }
        }
    }

    override fun onResume() {
        super.onResume()
        // 电视常年待机，回前台顺手刷新一次（30 秒内不会重复请求）
        viewModel.onResume()
    }
}
