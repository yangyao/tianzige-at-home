package com.tianzige.tv

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.viewModels
import androidx.compose.runtime.getValue
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.tianzige.tv.ui.TvRoot
import com.tianzige.tv.ui.theme.TzTheme
import com.tianzige.tv.vm.HomeViewModel

class MainActivity : ComponentActivity() {

    private val viewModel: HomeViewModel by viewModels()

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
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
